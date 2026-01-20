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

resource "aws_lambda_function" "contract_event_handler" {
  filename         = data.archive_file.contract_event_handler.output_path
  function_name    = "uni-prop-${var.stage}-contract-event-handler"
  role            = aws_iam_role.contract_event_handler_role.arn
  handler         = "Unicorn.Contracts.ContractService::Unicorn.Contracts.ContractService.ContractEventHandler::FunctionHandler"
  runtime         = "dotnet8"
  timeout         = 15
  memory_size     = 512
  architectures   = ["x86_64"]
  source_code_hash = data.archive_file.contract_event_handler.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE            = aws_dynamodb_table.contracts_table.name
      SERVICE_NAMESPACE         = data.aws_ssm_parameter.unicorn_contracts_namespace.value
      POWERTOOLS_LOGGER_CASE   = "PascalCase"
      POWERTOOLS_SERVICE_NAME   = data.aws_ssm_parameter.unicorn_contracts_namespace.value
      POWERTOOLS_TRACE_DISABLED = "false"
      POWERTOOLS_LOGGER_LOG_EVENT = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE = data.aws_ssm_parameter.unicorn_contracts_namespace.value
      POWERTOOLS_LOG_LEVEL     = "INFO"
      LOG_LEVEL                 = "INFO"
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








