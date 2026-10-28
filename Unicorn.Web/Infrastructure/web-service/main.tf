# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Unicorn Web service workload root (deployment phase 4: workloads).
#
# Serves property search through API Gateway and SearchFunction, accepts
# publication requests through API Gateway -> ingest SQS queue ->
# RequestApprovalFunction, and applies approval results from
# PublicationEvaluationCompleted events. PropertiesTable stores the listings.
#
# Reads:  /uni-prop/{UnicornWebNamespace, UnicornApprovalsNamespace},
#         /uni-prop/<stage>/{WebEventBus, WebEventBusArn}
# Needs:  the Shared api-gateway-account root for API execution logging.
# Layout: locals.tf holds naming, sam_build placeholders, and packaging inputs;
#         api.yaml.tpl is the OpenAPI body rendered into the REST API.

#################################################################################################
#### DATA SOURCES (skipped when sam_build = true; locals.tf supplies placeholders)
#################################################################################################

data "aws_caller_identity" "current" {
  count = var.sam_build ? 0 : 1
}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_ssm_parameter" "unicorn_web_namespace" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/UnicornWebNamespace"
}

data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/UnicornApprovalsNamespace"
}

data "aws_ssm_parameter" "web_event_bus_name" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/${var.stage}/WebEventBus"
}

data "aws_ssm_parameter" "web_event_bus_arn" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/${var.stage}/WebEventBusArn"
}

#################################################################################################
#### DYNAMODB TABLE
#################################################################################################

resource "aws_dynamodb_table" "properties_table" {
  name                        = "PropertiesTable-${var.stage}"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "PK"
  range_key                   = "SK"
  deletion_protection_enabled = local.is_prod

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  point_in_time_recovery {
    enabled = local.is_prod
  }
}

#################################################################################################
#### SQS QUEUES
#################################################################################################

resource "aws_sqs_queue" "unicorn_web_ingest_dlq" {
  name                      = "UnicornWebIngestDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "unicorn_web_ingest_queue" {
  name                       = "UnicornWebIngestQueue-${var.stage}"
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 20

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.unicorn_web_ingest_dlq.arn
    maxReceiveCount     = 1
  })
}

resource "aws_sqs_queue" "publication_evaluation_event_handler_dlq" {
  name                      = "PublicationEvaluationEventHandlerDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
}

#################################################################################################
#### LAMBDA FUNCTIONS
#################################################################################################

# Lambda packaging. `make package-service` writes a deterministic ZIP and manifest
# under .terraform/. On a normal plan or apply, the external data source checks
# that the package matches the current source and the precondition stops the run
# if it is missing or stale. During `make build` (sam_build = true) the
# null_resource builds the package instead, and the sam_metadata_* resources tell
# the SAM Terraform hook where each function's source and built ZIP live.
data "external" "search_package_freshness" {
  count   = var.sam_build ? 0 : 1
  program = ["python3", local.package_freshness_script_path]

  query = {
    repo_root     = local.repository_root_path
    package_path  = local.search_package_path
    manifest_path = local.search_package_manifest_path
  }
}

data "external" "publication_manager_package_freshness" {
  count   = var.sam_build ? 0 : 1
  program = ["python3", local.package_freshness_script_path]

  query = {
    repo_root     = local.repository_root_path
    package_path  = local.publication_manager_package_path
    manifest_path = local.publication_manager_package_manifest_path
  }
}

resource "null_resource" "build_search_service" {
  triggers = {
    source_hash = local.search_source_hash
  }

  lifecycle {
    precondition {
      condition     = var.sam_build ? true : data.external.search_package_freshness[0].result.fresh == "true"
      error_message = "Search Lambda deployment package is missing or stale. Run `make package-service` from Unicorn.Web and retry."
    }
  }

  provisioner "local-exec" {
    command = var.sam_build ? "python3 \"${local.package_script_path}\" --project \"${local.search_project_path}\" --build-dir \"${local.search_build_path}\" --output \"${local.search_package_path}\"" : "true"
  }
}

resource "null_resource" "build_publication_manager_service" {
  triggers = {
    source_hash = local.publication_manager_source_hash
  }

  lifecycle {
    precondition {
      condition     = var.sam_build ? true : data.external.publication_manager_package_freshness[0].result.fresh == "true"
      error_message = "Publication Manager Lambda deployment package is missing or stale. Run `make package-service` from Unicorn.Web and retry."
    }
  }

  provisioner "local-exec" {
    command = var.sam_build ? "python3 \"${local.package_script_path}\" --project \"${local.publication_manager_project_path}\" --build-dir \"${local.publication_manager_build_path}\" --output \"${local.publication_manager_package_path}\"" : "true"
  }
}

resource "null_resource" "sam_metadata_search_function" {
  triggers = {
    resource_name        = "aws_lambda_function.search_function"
    resource_type        = "ZIP_LAMBDA_FUNCTION"
    original_source_code = var.sam_build ? abspath(var.search_service_code_path) : var.search_service_code_path
    built_output_path    = var.sam_build ? abspath(local.search_package_path) : local.search_package_path
  }

  depends_on = [null_resource.build_search_service]
}

resource "null_resource" "sam_metadata_request_approval_function" {
  triggers = {
    resource_name        = "aws_lambda_function.request_approval_function"
    resource_type        = "ZIP_LAMBDA_FUNCTION"
    original_source_code = var.sam_build ? abspath(var.publication_manager_code_path) : var.publication_manager_code_path
    built_output_path    = var.sam_build ? abspath(local.publication_manager_package_path) : local.publication_manager_package_path
  }

  depends_on = [null_resource.build_publication_manager_service]
}

resource "null_resource" "sam_metadata_publication_evaluation_event_handler" {
  triggers = {
    resource_name        = "aws_lambda_function.publication_evaluation_event_handler"
    resource_type        = "ZIP_LAMBDA_FUNCTION"
    original_source_code = var.sam_build ? abspath(var.publication_manager_code_path) : var.publication_manager_code_path
    built_output_path    = var.sam_build ? abspath(local.publication_manager_package_path) : local.publication_manager_package_path
  }

  depends_on = [null_resource.build_publication_manager_service]
}

# SearchFunction: serves the read-only /search and /properties API routes.
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
          aws_dynamodb_table.properties_table.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "search_function_runtime_policy" {
  name = "LambdaRuntimeAccess"
  role = aws_iam_role.search_function_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${local.aws_account_id}:log-group:/aws/lambda/uni-prop-${var.stage}-search-function:*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "search_function_xray" {
  role       = aws_iam_role.search_function_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "search_function" {
  depends_on = [
    null_resource.build_search_service,
    aws_iam_role_policy.search_function_dynamodb_policy,
    aws_iam_role_policy.search_function_runtime_policy,
    aws_iam_role_policy_attachment.search_function_xray,
    aws_cloudwatch_log_group.search_function
  ]

  filename         = local.search_package_path
  function_name    = "uni-prop-${var.stage}-search-function"
  role             = aws_iam_role.search_function_role.arn
  handler          = "Unicorn.Web.SearchService::Unicorn.Web.SearchService.PropertySearchFunction::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = local.search_package_hash

  environment {
    variables = {
      DYNAMODB_TABLE                = aws_dynamodb_table.properties_table.name
      EVENT_BUS                     = local.web_event_bus_name
      SERVICE_NAMESPACE             = local.unicorn_web_namespace
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = local.unicorn_web_namespace
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = local.unicorn_web_namespace
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "search_function" {
  name              = "/aws/lambda/uni-prop-${var.stage}-search-function"
  retention_in_days = local.logs_retention_days
}

# RequestApprovalFunction: consumes /request_approval messages from the ingest
# queue and publishes PublicationApprovalRequested to the Web event bus.
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
        Resource = local.web_event_bus_arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.properties_table.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "request_approval_function_runtime_policy" {
  name = "LambdaRuntimeAccess"
  role = aws_iam_role.request_approval_function_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${local.aws_account_id}:log-group:/aws/lambda/uni-prop-${var.stage}-request-approval-function:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.unicorn_web_ingest_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "request_approval_function_xray" {
  role       = aws_iam_role.request_approval_function_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "request_approval_function" {
  depends_on = [
    null_resource.build_publication_manager_service,
    aws_iam_role_policy.request_approval_function_policy,
    aws_iam_role_policy.request_approval_function_runtime_policy,
    aws_iam_role_policy_attachment.request_approval_function_xray,
    aws_cloudwatch_log_group.request_approval_function
  ]

  filename         = local.publication_manager_package_path
  function_name    = "uni-prop-${var.stage}-request-approval-function"
  role             = aws_iam_role.request_approval_function_role.arn
  handler          = "Unicorn.Web.PublicationManagerService::Unicorn.Web.PublicationManagerService.RequestApprovalFunction::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = local.publication_manager_package_hash

  environment {
    variables = {
      DYNAMODB_TABLE                = aws_dynamodb_table.properties_table.name
      EVENT_BUS                     = local.web_event_bus_name
      SERVICE_NAMESPACE             = local.unicorn_web_namespace
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = local.unicorn_web_namespace
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = local.unicorn_web_namespace
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "request_approval_function" {
  name              = "/aws/lambda/uni-prop-${var.stage}-request-approval-function"
  retention_in_days = local.logs_retention_days
}

# SQS event sources do not support destination_config. Failed messages move to
# the queue's redrive DLQ instead; SAM excludes the matching rule (ES1001).
# tflint-ignore: aws_lambda_event_source_mapping_failure_destination
resource "aws_lambda_event_source_mapping" "request_approval_function_sqs" {
  event_source_arn = aws_sqs_queue.unicorn_web_ingest_queue.arn
  function_name    = aws_lambda_function.request_approval_function.arn
  batch_size       = 1
  enabled          = true

  scaling_config {
    maximum_concurrency = 5
  }
}

# PublicationEvaluationEventHandlerFunction: applies PublicationEvaluationCompleted
# results (forwarded from Approvals) to the property record.
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
          aws_dynamodb_table.properties_table.arn
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

resource "aws_iam_role_policy" "publication_evaluation_event_handler_runtime_policy" {
  name = "LambdaRuntimeAccess"
  role = aws_iam_role.publication_evaluation_event_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${local.aws_account_id}:log-group:/aws/lambda/uni-prop-${var.stage}-pub-eval-event-handler:*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "publication_evaluation_event_handler_xray" {
  role       = aws_iam_role.publication_evaluation_event_handler_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "publication_evaluation_event_handler" {
  depends_on = [
    null_resource.build_publication_manager_service,
    aws_iam_role_policy.publication_evaluation_event_handler_policy,
    aws_iam_role_policy.publication_evaluation_event_handler_runtime_policy,
    aws_iam_role_policy_attachment.publication_evaluation_event_handler_xray,
    aws_cloudwatch_log_group.publication_evaluation_event_handler
  ]

  filename         = local.publication_manager_package_path
  function_name    = "uni-prop-${var.stage}-pub-eval-event-handler"
  role             = aws_iam_role.publication_evaluation_event_handler_role.arn
  handler          = "Unicorn.Web.PublicationManagerService::Unicorn.Web.PublicationManagerService.PublicationEvaluationEventHandler::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = local.publication_manager_package_hash

  environment {
    variables = {
      DYNAMODB_TABLE                = aws_dynamodb_table.properties_table.name
      EVENT_BUS                     = local.web_event_bus_name
      SERVICE_NAMESPACE             = local.unicorn_web_namespace
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = local.unicorn_web_namespace
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = local.unicorn_web_namespace
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "publication_evaluation_event_handler" {
  name              = "/aws/lambda/uni-prop-${var.stage}-pub-eval-event-handler"
  retention_in_days = local.logs_retention_days
}

# The literal rule name mirrors the SAM RuleName.
resource "aws_cloudwatch_event_rule" "publication_evaluation_completed" {
  name           = "unicorn-web-PublicationEvaluationCompleted"
  event_bus_name = local.web_event_bus_name

  event_pattern = jsonencode({
    source      = [local.unicorn_approvals_namespace]
    detail-type = ["PublicationEvaluationCompleted"]
  })
}

# EventBridge invokes the function asynchronously, so failed invocations go to
# the function's on-failure destination (event invoke config below). SAM
# defines no target DLQ here either.
# tflint-ignore: aws_cloudwatch_event_target_no_dlq
resource "aws_cloudwatch_event_target" "publication_evaluation_completed" {
  rule           = aws_cloudwatch_event_rule.publication_evaluation_completed.name
  event_bus_name = local.web_event_bus_name
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

resource "aws_lambda_function_event_invoke_config" "publication_evaluation_event_handler" {
  function_name = aws_lambda_function.publication_evaluation_event_handler.function_name

  destination_config {
    on_failure {
      destination = aws_sqs_queue.publication_evaluation_event_handler_dlq.arn
    }
  }
}

#################################################################################################
#### API GATEWAY
#################################################################################################

# The REST API (api.yaml.tpl) sends /request_approval to the ingest queue and
# proxies search routes to SearchFunction, both through this role.
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
}

resource "aws_api_gateway_rest_api" "unicorn_web_api" {
  # SAM sets no Name, so API Gateway names the API from the OpenAPI info.title.
  # Terraform's name argument overrides the title, so it repeats it here.
  name        = "Unicorn Web API"
  description = "Unicorn Web API"
  body        = local.api_openapi_spec

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  lifecycle {
    create_before_destroy = true
  }
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
  name              = "/aws/events/${var.stage}/${local.unicorn_web_namespace}-catchall"
  retention_in_days = local.logs_retention_days
}

resource "aws_cloudwatch_event_rule" "unicorn_web_catch_all" {
  name           = "${local.unicorn_web_namespace}-CatchAllEvents"
  description    = "Catch all events published by the Web service."
  event_bus_name = local.web_event_bus_name
  state          = "ENABLED"

  event_pattern = jsonencode({
    account = [local.aws_account_id]
    source  = [local.unicorn_web_namespace]
  })
}

# The catch-all rule exists for debugging and writes to a log group; SAM excludes
# the matching serverless rule (ES4000), so this target has no DLQ either.
# tflint-ignore: aws_cloudwatch_event_target_no_dlq
resource "aws_cloudwatch_event_target" "unicorn_web_catch_all" {
  rule           = aws_cloudwatch_event_rule.unicorn_web_catch_all.name
  event_bus_name = local.web_event_bus_name
  target_id      = "UnicornWebCatchAllLogGroupTarget-${var.stage}"
  arn            = aws_cloudwatch_log_group.unicorn_web_catch_all.arn
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
        Resource = "${aws_cloudwatch_log_group.unicorn_web_catch_all.arn}:*"
      }
    ]
  })
}
