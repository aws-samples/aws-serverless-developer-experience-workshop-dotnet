data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_ssm_parameter" "unicorn_contracts_namespace" {
  name = "/uni-prop/UnicornContractsNamespace"
}

data "aws_ssm_parameter" "contracts_event_bus_arn" {
  name = "/uni-prop/${var.stage}/ContractsEventBusArn"
}

data "aws_ssm_parameter" "contracts_event_bus_name" {
  name = "/uni-prop/${var.stage}/ContractsEventBus"
}

#################################################################################################
#### DYNAMODB TABLE
#################################################################################################

resource "aws_dynamodb_table" "contracts_table" {
  name         = "ContractsTable-${var.stage}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PropertyId"

  attribute {
    name = "PropertyId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = local.common_tags
}

#################################################################################################
#### SQS QUEUES
#################################################################################################

resource "aws_sqs_queue" "unicorn_contracts_ingest_dlq" {
  name                      = "UnicornContractsIngestDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "unicorn_contracts_ingest_queue" {
  name                       = "UnicornContractsIngestQueue-${var.stage}"
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 20
  tags                       = local.common_tags

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.unicorn_contracts_ingest_dlq.arn
    maxReceiveCount     = 1
  })
}

resource "aws_sqs_queue" "contracts_table_stream_to_event_pipe_dlq" {
  name                      = "ContractsTableStreamToEventPipeDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
  tags                      = local.common_tags
}

#################################################################################################
#### LAMBDA FUNCTION
#################################################################################################

data "archive_file" "contract_event_handler" {
  type        = "zip"
  source_dir  = var.lambda_code_path
  output_path = "${path.module}/.terraform/contract-event-handler.zip"
  excludes    = ["bin", "obj", ".aws-sam"]
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

  tags = local.common_tags
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

resource "aws_iam_role_policy_attachment" "contract_event_handler_xray" {
  role       = aws_iam_role.contract_event_handler_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "contract_event_handler" {
  filename         = data.archive_file.contract_event_handler.output_path
  function_name    = "uni-prop-${var.stage}-contract-event-handler"
  role             = aws_iam_role.contract_event_handler_role.arn
  handler          = "Unicorn.Contracts.ContractService::Unicorn.Contracts.ContractService.ContractEventHandler::FunctionHandler"
  runtime          = "dotnet8"
  timeout          = 15
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = data.archive_file.contract_event_handler.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE                = aws_dynamodb_table.contracts_table.name
      SERVICE_NAMESPACE             = data.aws_ssm_parameter.unicorn_contracts_namespace.value
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = data.aws_ssm_parameter.unicorn_contracts_namespace.value
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = data.aws_ssm_parameter.unicorn_contracts_namespace.value
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "contract_event_handler" {
  name              = "/aws/lambda/${aws_lambda_function.contract_event_handler.function_name}"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
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

resource "aws_iam_role" "unicorn_contracts_api_gw_account_config_role" {
  name = "uni-prop-${var.stage}-contracts-api-gw-account-config-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "api_gw_cloudwatch_logs" {
  role       = aws_iam_role.unicorn_contracts_api_gw_account_config_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "contracts_api_gw_account_config" {
  cloudwatch_role_arn = aws_iam_role.unicorn_contracts_api_gw_account_config_role.arn
}

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

  tags = local.common_tags
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
  tags              = local.common_tags
}

resource "aws_api_gateway_rest_api" "unicorn_contracts_api" {
  name        = "uni-prop-${var.stage}-contracts-api"
  description = "Unicorn Contracts API"
  body        = local.api_openapi_spec

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags

  depends_on = [
    aws_api_gateway_account.contracts_api_gw_account_config
  ]
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
      requestId                           = "$context.requestId"
      "integration-error"                 = "$context.integration.error"
      "integration-status"                = "$context.integration.status"
      "integration-latency"               = "$context.integration.latency"
      "integration-requestId"             = "$context.integration.requestId"
      "integration-integrationStatus"     = "$context.integration.integrationStatus"
      "response-latency"                  = "$context.responseLatency"
      status                              = "$context.status"
    })
  }

  xray_tracing_enabled = true

  tags = local.common_tags
}

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
  name              = "/aws/events/${var.stage}/${data.aws_ssm_parameter.unicorn_contracts_namespace.value}-catchall"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_event_rule" "unicorn_contracts_catch_all" {
  name           = "${data.aws_ssm_parameter.unicorn_contracts_namespace.value}-CatchAllEvents"
  description    = "Catch all events published by the Contracts service."
  event_bus_name = data.aws_ssm_parameter.contracts_event_bus_name.value
  state          = "ENABLED"

  event_pattern = jsonencode({
    account = [data.aws_caller_identity.current.account_id]
    source  = [data.aws_ssm_parameter.unicorn_contracts_namespace.value]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "unicorn_contracts_catch_all" {
  rule           = aws_cloudwatch_event_rule.unicorn_contracts_catch_all.name
  event_bus_name = data.aws_ssm_parameter.contracts_event_bus_name.value
  target_id      = "UnicornContractsCatchAllLogGroupTarget-${var.stage}"
  arn            = aws_cloudwatch_log_group.unicorn_contracts_catch_all.arn
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_cloudwatch_log_group_policy" {
  policy_name = "EvBToCWLogs-${var.stage}-contracts-catchall"

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
  tags              = local.common_tags
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
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = local.common_tags
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
        Resource = data.aws_ssm_parameter.contracts_event_bus_arn.value
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
  target   = data.aws_ssm_parameter.contracts_event_bus_arn.value

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
              contract_status = {
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
      source      = data.aws_ssm_parameter.unicorn_contracts_namespace.value
    }

    input_template = jsonencode({
      PropertyId             = "<$.dynamodb.Keys.PropertyId.S>"
      ContractId             = "<$.dynamodb.NewImage.ContractId.S>"
      ContractStatus         = "<$.dynamodb.NewImage.ContractStatus.S>"
      ContractLastModifiedOn = "<$.dynamodb.NewImage.ContractLastModifiedOn.S>"
    })
  }

  log_configuration {
    cloudwatch_logs_log_destination {
      log_group_arn = aws_cloudwatch_log_group.contracts_table_stream_to_event_pipe.arn
    }
    level = "ERROR"
  }

  tags = local.common_tags
}
