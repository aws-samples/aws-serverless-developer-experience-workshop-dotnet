data "archive_file" "search_service" {
  type        = "zip"
  source_dir  = var.search_service_code_path
  output_path = "${path.module}/.terraform/search-service.zip"
  excludes    = ["bin", "obj", ".aws-sam"]
}

data "archive_file" "publication_manager_service" {
  type        = "zip"
  source_dir  = var.publication_manager_service_code_path
  output_path = "${path.module}/.terraform/publication-manager-service.zip"
  excludes    = ["bin", "obj", ".aws-sam"]
}

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

resource "aws_lambda_function" "search_function" {
  filename         = data.archive_file.search_service.output_path
  function_name    = "uni-prop-${var.stage}-search-function"
  role            = aws_iam_role.search_function_role.arn
  handler         = "Unicorn.Web.SearchService::Unicorn.Web.SearchService.PropertySearchFunction::FunctionHandler"
  runtime         = "dotnet8"
  timeout         = 10
  memory_size     = 512
  architectures   = ["x86_64"]
  source_code_hash = data.archive_file.search_service.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE            = aws_dynamodb_table.properties_table.name
      EVENT_BUS                = data.aws_ssm_parameter.web_event_bus.value
      SERVICE_NAMESPACE         = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOGGER_CASE   = "PascalCase"
      POWERTOOLS_SERVICE_NAME   = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_TRACE_DISABLED = "false"
      POWERTOOLS_LOGGER_LOG_EVENT = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOG_LEVEL     = "INFO"
      LOG_LEVEL                = "INFO"
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
      },
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = "arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:event-bus/${data.aws_ssm_parameter.web_event_bus.value}"
      }
    ]
  })
}

resource "aws_lambda_function" "request_approval_function" {
  filename         = data.archive_file.publication_manager_service.output_path
  function_name    = "uni-prop-${var.stage}-request-approval-function"
  role            = aws_iam_role.request_approval_function_role.arn
  handler         = "Unicorn.Web.PublicationManagerService::Unicorn.Web.PublicationManagerService.RequestApprovalFunction::FunctionHandler"
  runtime         = "dotnet8"
  timeout         = 10
  memory_size     = 512
  architectures   = ["x86_64"]
  source_code_hash = data.archive_file.publication_manager_service.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE            = aws_dynamodb_table.properties_table.name
      EVENT_BUS                = data.aws_ssm_parameter.web_event_bus.value
      SERVICE_NAMESPACE         = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOGGER_CASE   = "PascalCase"
      POWERTOOLS_SERVICE_NAME   = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_TRACE_DISABLED = "false"
      POWERTOOLS_LOGGER_LOG_EVENT = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOG_LEVEL     = "INFO"
      LOG_LEVEL                = "INFO"
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

resource "aws_iam_role" "publication_evaluation_event_handler_role" {
  name = "uni-prop-${var.stage}-publication-evaluation-event-handler-role"

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

resource "aws_iam_role_policy" "publication_evaluation_event_handler_dynamodb_policy" {
  name = "DynamoDBCrudAccess"
  role = aws_iam_role.publication_evaluation_event_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
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

resource "aws_lambda_function" "publication_evaluation_event_handler" {
  filename         = data.archive_file.publication_manager_service.output_path
  function_name    = "uni-prop-${var.stage}-publication-evaluation-event-handler"
  role            = aws_iam_role.publication_evaluation_event_handler_role.arn
  handler         = "Unicorn.Web.PublicationManagerService::Unicorn.Web.PublicationManagerService.PublicationEvaluationEventHandler::FunctionHandler"
  runtime         = "dotnet8"
  timeout         = 10
  memory_size     = 512
  architectures   = ["x86_64"]
  source_code_hash = data.archive_file.publication_manager_service.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE            = aws_dynamodb_table.properties_table.name
      EVENT_BUS                = data.aws_ssm_parameter.web_event_bus.value
      SERVICE_NAMESPACE         = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOGGER_CASE   = "PascalCase"
      POWERTOOLS_SERVICE_NAME   = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_TRACE_DISABLED = "false"
      POWERTOOLS_LOGGER_LOG_EVENT = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE = data.aws_ssm_parameter.unicorn_web_namespace.value
      POWERTOOLS_LOG_LEVEL     = "INFO"
      LOG_LEVEL                = "INFO"
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

resource "aws_lambda_function_event_invoke_config" "publication_evaluation_event_handler" {
  function_name = aws_lambda_function.publication_evaluation_event_handler.function_name

  destination_config {
    on_failure {
      destination = aws_sqs_queue.publication_evaluation_event_handler_dlq.arn
    }
  }
}








