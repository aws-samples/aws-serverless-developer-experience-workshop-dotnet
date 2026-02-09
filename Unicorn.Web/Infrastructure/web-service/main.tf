data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_ssm_parameter" "unicorn_web_namespace" {
  name = "/uni-prop/UnicornWebNamespace"
}

data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name = "/uni-prop/UnicornApprovalsNamespace"
}

data "aws_ssm_parameter" "web_event_bus_name" {
  name = "/uni-prop/${var.stage}/WebEventBus"
}

data "aws_ssm_parameter" "web_event_bus_arn" {
  name = "/uni-prop/${var.stage}/WebEventBusArn"
}

#################################################################################################
#### DYNAMODB TABLE
#################################################################################################

resource "aws_dynamodb_table" "properties_table" {
  name         = "PropertiesTable-${var.stage}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  tags = local.common_tags
}

#################################################################################################
#### SQS QUEUES
#################################################################################################

resource "aws_sqs_queue" "unicorn_web_ingest_dlq" {
  name                      = "UnicornWebIngestDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "unicorn_web_ingest_queue" {
  name                       = "UnicornWebIngestQueue-${var.stage}"
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 20
  tags                       = local.common_tags

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.unicorn_web_ingest_dlq.arn
    maxReceiveCount     = 1
  })
}

resource "aws_sqs_queue" "publication_evaluation_event_handler_dlq" {
  name                      = "PublicationEvaluationEventHandlerDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
  tags                      = local.common_tags
}

#################################################################################################
#### LAMBDA FUNCTIONS
#################################################################################################

data "archive_file" "search_service" {
  type        = "zip"
  source_dir  = var.search_service_code_path
  output_path = "${path.module}/.terraform/search-service.zip"
  excludes    = ["bin", "obj", ".aws-sam"]
}

data "archive_file" "publication_manager_service" {
  type        = "zip"
  source_dir  = var.publication_manager_code_path
  output_path = "${path.module}/.terraform/publication-manager-service.zip"
  excludes    = ["bin", "obj", ".aws-sam"]
}

# SearchFunction
resource "aws_iam_role" "search_function_role" {
  name = "uni-prop-${var.stage}-search-function-role"

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

resource "aws_iam_role_policy" "search_function_dynamodb_policy" {
  name = "DynamoDBReadAccess"
  role = aws_iam_role.search_function_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.properties_table.arn,
          "${aws_dynamodb_table.properties_table.arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "search_function_xray" {
  role       = aws_iam_role.search_function_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "search_function" {
  filename         = data.archive_file.search_service.output_path
  function_name    = "uni-prop-${var.stage}-search-function"
  role             = aws_iam_role.search_function_role.arn
  handler          = "Unicorn.Web.SearchService::Unicorn.Web.SearchService.PropertySearchFunction::FunctionHandler"
  runtime          = "dotnet8"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = data.archive_file.search_service.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE                = aws_dynamodb_table.properties_table.name
      EVENT_BUS                     = data.aws_ssm_parameter.web_event_bus_name.value
      SERVICE_NAMESPACE             = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "search_function" {
  name              = "/aws/lambda/${aws_lambda_function.search_function.function_name}"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

# RequestApprovalFunction
resource "aws_iam_role" "request_approval_function_role" {
  name = "uni-prop-${var.stage}-request-approval-function-role"

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

resource "aws_iam_role_policy" "request_approval_function_policy" {
  name = "RequestApprovalFunctionPolicy"
  role = aws_iam_role.request_approval_function_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = data.aws_ssm_parameter.web_event_bus_arn.value
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.properties_table.arn,
          "${aws_dynamodb_table.properties_table.arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "request_approval_function_xray" {
  role       = aws_iam_role.request_approval_function_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "request_approval_function" {
  filename         = data.archive_file.publication_manager_service.output_path
  function_name    = "uni-prop-${var.stage}-request-approval-function"
  role             = aws_iam_role.request_approval_function_role.arn
  handler          = "Unicorn.Web.PublicationManagerService::Unicorn.Web.PublicationManagerService.RequestApprovalFunction::FunctionHandler"
  runtime          = "dotnet8"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = data.archive_file.publication_manager_service.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE                = aws_dynamodb_table.properties_table.name
      EVENT_BUS                     = data.aws_ssm_parameter.web_event_bus_name.value
      SERVICE_NAMESPACE             = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "request_approval_function" {
  name              = "/aws/lambda/${aws_lambda_function.request_approval_function.function_name}"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_lambda_event_source_mapping" "request_approval_function_sqs" {
  event_source_arn = aws_sqs_queue.unicorn_web_ingest_queue.arn
  function_name    = aws_lambda_function.request_approval_function.arn
  batch_size       = 1
  enabled          = true

  scaling_config {
    maximum_concurrency = 5
  }
}

# PublicationEvaluationEventHandlerFunction
resource "aws_iam_role" "publication_evaluation_event_handler_role" {
  name = "uni-prop-${var.stage}-pub-eval-event-handler-role"

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

resource "aws_iam_role_policy" "publication_evaluation_event_handler_policy" {
  name = "PublicationEvaluationEventHandlerPolicy"
  role = aws_iam_role.publication_evaluation_event_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.properties_table.arn,
          "${aws_dynamodb_table.properties_table.arn}/index/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.publication_evaluation_event_handler_dlq.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "publication_evaluation_event_handler_xray" {
  role       = aws_iam_role.publication_evaluation_event_handler_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "publication_evaluation_event_handler" {
  filename         = data.archive_file.publication_manager_service.output_path
  function_name    = "uni-prop-${var.stage}-pub-eval-event-handler"
  role             = aws_iam_role.publication_evaluation_event_handler_role.arn
  handler          = "Unicorn.Web.PublicationManagerService::Unicorn.Web.PublicationManagerService.PublicationEvaluationEventHandler::FunctionHandler"
  runtime          = "dotnet8"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = data.archive_file.publication_manager_service.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE                = aws_dynamodb_table.properties_table.name
      EVENT_BUS                     = data.aws_ssm_parameter.web_event_bus_name.value
      SERVICE_NAMESPACE             = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "publication_evaluation_event_handler" {
  name              = "/aws/lambda/${aws_lambda_function.publication_evaluation_event_handler.function_name}"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_event_rule" "publication_evaluation_completed" {
  name           = "unicorn-web-PublicationEvaluationCompleted"
  event_bus_name = data.aws_ssm_parameter.web_event_bus_name.value

  event_pattern = jsonencode({
    source      = [data.aws_ssm_parameter.unicorn_approvals_namespace.value]
    detail-type = ["PublicationEvaluationCompleted"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "publication_evaluation_completed" {
  rule           = aws_cloudwatch_event_rule.publication_evaluation_completed.name
  event_bus_name = data.aws_ssm_parameter.web_event_bus_name.value
  target_id      = "PublicationEvaluationEventHandler"
  arn            = aws_lambda_function.publication_evaluation_event_handler.arn
}

resource "aws_lambda_permission" "publication_evaluation_completed_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.publication_evaluation_event_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.publication_evaluation_completed.arn
}

#################################################################################################
#### API GATEWAY
#################################################################################################

resource "aws_iam_role" "unicorn_web_api_gw_account_config_role" {
  name = "uni-prop-${var.stage}-web-api-gw-account-config-role"

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
  role       = aws_iam_role.unicorn_web_api_gw_account_config_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "web_api_gw_account_config" {
  cloudwatch_role_arn = aws_iam_role.unicorn_web_api_gw_account_config_role.arn
}

resource "aws_iam_role" "unicorn_web_api_integration_role" {
  name = "uni-prop-${var.stage}-web-api-integration-role"

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

resource "aws_iam_role_policy" "unicorn_web_api_integration_sqs_policy" {
  name = "AllowSqsIntegration"
  role = aws_iam_role.unicorn_web_api_integration_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.unicorn_web_ingest_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "unicorn_web_api_integration_lambda_policy" {
  name = "AllowLambdaInvocation"
  role = aws_iam_role.unicorn_web_api_integration_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.search_function.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "unicorn_web_api" {
  name              = "/aws/apigateway/uni-prop-${var.stage}-web-api"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_api_gateway_rest_api" "unicorn_web_api" {
  name        = "uni-prop-${var.stage}-web-api"
  description = "Unicorn Web API"
  body        = local.api_openapi_spec

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags

  depends_on = [
    aws_api_gateway_account.web_api_gw_account_config
  ]
}

resource "aws_api_gateway_deployment" "unicorn_web_api" {
  rest_api_id = aws_api_gateway_rest_api.unicorn_web_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.unicorn_web_api.body,
      aws_api_gateway_rest_api.unicorn_web_api.name,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "unicorn_web_api" {
  deployment_id = aws_api_gateway_deployment.unicorn_web_api.id
  rest_api_id   = aws_api_gateway_rest_api.unicorn_web_api.id
  stage_name    = var.stage

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.unicorn_web_api.arn
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

resource "aws_api_gateway_method_settings" "unicorn_web_api" {
  rest_api_id = aws_api_gateway_rest_api.unicorn_web_api.id
  stage_name  = aws_api_gateway_stage.unicorn_web_api.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    logging_level          = local.log_level
    throttling_burst_limit = 10
    throttling_rate_limit  = 100
  }
}

#################################################################################################
#### EVENTBRIDGE CATCHALL
#################################################################################################

resource "aws_cloudwatch_log_group" "unicorn_web_catch_all" {
  name              = "/aws/events/${var.stage}/${data.aws_ssm_parameter.unicorn_web_namespace.value}-catchall"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_event_rule" "unicorn_web_catch_all" {
  name           = "${data.aws_ssm_parameter.unicorn_web_namespace.value}-CatchAllEvents"
  description    = "Catch all events published by the Web service."
  event_bus_name = data.aws_ssm_parameter.web_event_bus_name.value
  state          = "ENABLED"

  event_pattern = jsonencode({
    account = [data.aws_caller_identity.current.account_id]
    source  = [data.aws_ssm_parameter.unicorn_web_namespace.value]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "unicorn_web_catch_all" {
  rule           = aws_cloudwatch_event_rule.unicorn_web_catch_all.name
  event_bus_name = data.aws_ssm_parameter.web_event_bus_name.value
  target_id      = "UnicornWebCatchAllLogGroupTarget-${var.stage}"
  arn            = aws_cloudwatch_log_group.unicorn_web_catch_all.arn
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_cloudwatch_log_group_policy" {
  policy_name = "EvBToCWLogs-${var.stage}-web-catchall"

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
        Resource = "${aws_cloudwatch_log_group.unicorn_web_catch_all.arn}:*"
      }
    ]
  })
}
