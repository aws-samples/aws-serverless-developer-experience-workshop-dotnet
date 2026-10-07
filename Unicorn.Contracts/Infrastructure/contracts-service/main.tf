data "aws_caller_identity" "current" {
  count = var.sam_build ? 0 : 1
}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_ssm_parameter" "unicorn_contracts_namespace" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/UnicornContractsNamespace"
}

data "aws_ssm_parameter" "contracts_event_bus_arn" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/${var.stage}/ContractsEventBusArn"
}

data "aws_ssm_parameter" "contracts_event_bus_name" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/${var.stage}/ContractsEventBus"
}

#################################################################################################
#### DYNAMODB TABLE
#################################################################################################

resource "aws_dynamodb_table" "contracts_table" {
  name                        = "ContractsTable-${var.stage}"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "PropertyId"
  deletion_protection_enabled = local.is_prod

  attribute {
    name = "PropertyId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = local.is_prod
  }
}

#################################################################################################
#### SQS QUEUES
#################################################################################################

resource "aws_sqs_queue" "unicorn_contracts_ingest_dlq" {
  name                      = "UnicornContractsIngestDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "unicorn_contracts_ingest_queue" {
  name                       = "UnicornContractsIngestQueue-${var.stage}"
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.unicorn_contracts_ingest_dlq.arn
    maxReceiveCount     = 1
  })
}

resource "aws_sqs_queue" "contracts_table_stream_to_event_pipe_dlq" {
  name                      = "ContractsTableStreamToEventPipeDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
}

#################################################################################################
#### LAMBDA FUNCTION
#################################################################################################

data "external" "lambda_package_freshness" {
  count   = var.sam_build ? 0 : 1
  program = ["python3", local.package_freshness_script_path]

  query = {
    repo_root     = local.repository_root_path
    package_path  = local.lambda_package_path
    manifest_path = local.lambda_package_manifest_path
  }
}

resource "null_resource" "build_contract_event_handler" {
  triggers = {
    source_hash = local.lambda_source_hash
  }

  lifecycle {
    precondition {
      condition     = var.sam_build ? true : data.external.lambda_package_freshness[0].result.fresh == "true"
      error_message = "Lambda deployment package is missing or stale. Run `make package-service` from Unicorn.Contracts and retry."
    }
  }

  provisioner "local-exec" {
    command = var.sam_build ? "python3 \"${local.package_script_path}\" --project \"${local.lambda_project_path}\" --build-dir \"${local.lambda_build_path}\" --output \"${local.lambda_package_path}\"" : "true"
  }
}

resource "null_resource" "sam_metadata_contract_event_handler" {
  triggers = {
    resource_name        = "aws_lambda_function.contract_event_handler"
    resource_type        = "ZIP_LAMBDA_FUNCTION"
    original_source_code = var.sam_build ? abspath(var.lambda_code_path) : var.lambda_code_path
    built_output_path    = var.sam_build ? abspath(local.lambda_package_path) : local.lambda_package_path
  }

  depends_on = [null_resource.build_contract_event_handler]
}

resource "aws_iam_role" "contract_event_handler_role" {
  name = "uni-prop-${var.stage}-contract-event-handler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "contract_event_handler_dynamodb_policy" {
  name = "DynamoDBAccess"
  role = aws_iam_role.contract_event_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.contracts_table.arn,
          "${aws_dynamodb_table.contracts_table.arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "contract_event_handler_runtime_policy" {
  name = "LambdaRuntimeAccess"
  role = aws_iam_role.contract_event_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${local.aws_account_id}:log-group:/aws/lambda/uni-prop-${var.stage}-contract-event-handler:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.unicorn_contracts_ingest_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "contract_event_handler_xray" {
  role       = aws_iam_role.contract_event_handler_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "contract_event_handler" {
  depends_on = [
    null_resource.build_contract_event_handler,
    aws_iam_role_policy.contract_event_handler_dynamodb_policy,
    aws_iam_role_policy.contract_event_handler_runtime_policy,
    aws_iam_role_policy_attachment.contract_event_handler_xray,
    aws_cloudwatch_log_group.contract_event_handler
  ]

  filename         = local.lambda_package_path
  function_name    = "uni-prop-${var.stage}-contract-event-handler"
  role             = aws_iam_role.contract_event_handler_role.arn
  handler          = "Unicorn.Contracts.ContractService::Unicorn.Contracts.ContractService.ContractEventHandler::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 15
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = local.lambda_package_hash

  environment {
    variables = {
      DYNAMODB_TABLE                = aws_dynamodb_table.contracts_table.name
      SERVICE_NAMESPACE             = local.unicorn_contracts_namespace
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = local.unicorn_contracts_namespace
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = local.unicorn_contracts_namespace
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "contract_event_handler" {
  name              = "/aws/lambda/uni-prop-${var.stage}-contract-event-handler"
  retention_in_days = local.logs_retention_days
}

resource "aws_lambda_event_source_mapping" "contract_event_handler_sqs" {
  event_source_arn = aws_sqs_queue.unicorn_contracts_ingest_queue.arn
  function_name    = aws_lambda_function.contract_event_handler.arn
  batch_size       = 1
  enabled          = true

  scaling_config {
    maximum_concurrency = 5
  }
}

#################################################################################################
#### API GATEWAY
#################################################################################################

resource "aws_iam_role" "unicorn_contracts_api_integration_role" {
  name = "uni-prop-${var.stage}-contracts-api-integration-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "unicorn_contracts_api_integration_sqs_policy" {
  name = "AllowSqsIntegration"
  role = aws_iam_role.unicorn_contracts_api_integration_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.unicorn_contracts_ingest_queue.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "unicorn_contracts_api" {
  name              = "/aws/apigateway/uni-prop-${var.stage}-contracts-api"
  retention_in_days = local.logs_retention_days
}

resource "aws_api_gateway_rest_api" "unicorn_contracts_api" {
  # SAM sets no Name, so API Gateway names the API from the OpenAPI info.title.
  # Terraform's name argument overrides the title, so it repeats it here.
  name        = "Unicorn Contracts API"
  description = "Unicorn Contracts API"
  body        = local.api_openapi_spec

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_deployment" "unicorn_contracts_api" {
  rest_api_id = aws_api_gateway_rest_api.unicorn_contracts_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.unicorn_contracts_api.body,
      aws_api_gateway_rest_api.unicorn_contracts_api.name,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "unicorn_contracts_api" {
  deployment_id = aws_api_gateway_deployment.unicorn_contracts_api.id
  rest_api_id   = aws_api_gateway_rest_api.unicorn_contracts_api.id
  stage_name    = var.stage

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.unicorn_contracts_api.arn
    format = jsonencode({
      requestId                       = "$context.requestId"
      "integration-error"             = "$context.integration.error"
      "integration-status"            = "$context.integration.status"
      "integration-latency"           = "$context.integration.latency"
      "integration-requestId"         = "$context.integration.requestId"
      "integration-integrationStatus" = "$context.integration.integrationStatus"
      "response-latency"              = "$context.responseLatency"
      status                          = "$context.status"
    })
  }

  xray_tracing_enabled = true
}

# API Gateway execution logging depends on the account-level CloudWatch role in
# Unicorn.Shared/Infrastructure/api-gateway-account.
resource "aws_api_gateway_method_settings" "unicorn_contracts_api" {
  rest_api_id = aws_api_gateway_rest_api.unicorn_contracts_api.id
  stage_name  = aws_api_gateway_stage.unicorn_contracts_api.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = local.log_level
    throttling_burst_limit = 10
    throttling_rate_limit  = 100
  }
}

#################################################################################################
#### EVENTBRIDGE
#################################################################################################

resource "aws_cloudwatch_log_group" "unicorn_contracts_catch_all" {
  name              = "/aws/events/${var.stage}/${local.unicorn_contracts_namespace}-catchall"
  retention_in_days = local.logs_retention_days
}

resource "aws_cloudwatch_event_rule" "unicorn_contracts_catch_all" {
  name           = "${local.unicorn_contracts_namespace}-CatchAllEvents"
  description    = "Catch all events published by the Contracts service."
  event_bus_name = local.contracts_event_bus_name
  state          = "ENABLED"

  event_pattern = jsonencode({
    account = [local.aws_account_id]
    source  = [local.unicorn_contracts_namespace]
  })
}

resource "aws_cloudwatch_event_target" "unicorn_contracts_catch_all" {
  rule           = aws_cloudwatch_event_rule.unicorn_contracts_catch_all.name
  event_bus_name = local.contracts_event_bus_name
  target_id      = "UnicornContractsCatchAllLogGroupTarget-${var.stage}"
  arn            = aws_cloudwatch_log_group.unicorn_contracts_catch_all.arn
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_cloudwatch_log_group_policy" {
  policy_name = "EvBToCWLogs-${local.stack_name}"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "delivery.logs.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.unicorn_contracts_catch_all.arn}:*"
      }
    ]
  })
}

#################################################################################################
#### EVENTBRIDGE PIPES (DynamoDB Streams -> EventBridge)
#################################################################################################

resource "aws_cloudwatch_log_group" "contracts_table_stream_to_event_pipe" {
  name              = "/aws/pipes/uni-prop-${var.stage}-contracts-table-stream-to-event-pipe"
  retention_in_days = local.logs_retention_days
}

resource "aws_iam_role" "contracts_table_stream_to_event_pipe_role" {
  name = "uni-prop-${var.stage}-contracts-table-stream-to-event-pipe-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "pipes.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.aws_account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "contracts_table_stream_to_event_pipe_policy" {
  name = "ContractsTableStreamToEventPipePolicy"
  role = aws_iam_role.contracts_table_stream_to_event_pipe_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:ListStreams"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ]
        Resource = aws_dynamodb_table.contracts_table.stream_arn
      },
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = local.contracts_event_bus_arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.contracts_table_stream_to_event_pipe_dlq.arn
      }
    ]
  })
}

resource "aws_pipes_pipe" "contracts_table_stream_to_event_pipe" {
  name     = "uni-prop-${var.stage}-contracts-table-stream-to-event-pipe"
  role_arn = aws_iam_role.contracts_table_stream_to_event_pipe_role.arn
  source   = aws_dynamodb_table.contracts_table.stream_arn
  target   = local.contracts_event_bus_arn

  source_parameters {
    dynamodb_stream_parameters {
      maximum_retry_attempts = 3
      batch_size             = 1
      starting_position      = "LATEST"

      dead_letter_config {
        arn = aws_sqs_queue.contracts_table_stream_to_event_pipe_dlq.arn
      }
    }

    filter_criteria {
      filter {
        pattern = jsonencode({
          eventName = ["INSERT", "MODIFY"]
          dynamodb = {
            NewImage = {
              ContractStatus = {
                S = ["DRAFT", "APPROVED"]
              }
            }
          }
        })
      }
    }
  }

  target_parameters {
    eventbridge_event_bus_parameters {
      detail_type = "ContractStatusChanged"
      source      = local.unicorn_contracts_namespace
    }

    input_template = <<-JSON
      {
        "PropertyId": <$.dynamodb.Keys.PropertyId.S>,
        "ContractId": <$.dynamodb.NewImage.ContractId.S>,
        "ContractStatus": <$.dynamodb.NewImage.ContractStatus.S>,
        "ContractLastModifiedOn": <$.dynamodb.NewImage.ContractLastModifiedOn.S>
      }
    JSON
  }

  log_configuration {
    cloudwatch_logs_log_destination {
      log_group_arn = aws_cloudwatch_log_group.contracts_table_stream_to_event_pipe.arn
    }
    level = "ERROR"
  }
}
