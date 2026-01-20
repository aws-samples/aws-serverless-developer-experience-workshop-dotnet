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

  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
  ]

  tags = local.common_tags
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

locals {
  api_openapi_spec = templatefile("${path.module}/api.yaml.tpl", {
    UnicornContractsApiIntegrationRoleArn = aws_iam_role.unicorn_contracts_api_integration_role.arn
    UnicornContractsIngestQueueName       = aws_sqs_queue.unicorn_contracts_ingest_queue.name
    AWS_Region                            = data.aws_region.current.id
    AWS_AccountId                         = data.aws_caller_identity.current.account_id
  })
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
  stage_name  = var.stage

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
      requestId                    = "$context.requestId"
      "integration-error"         = "$context.integration.error"
      "integration-status"        = "$context.integration.status"
      "integration-latency"       = "$context.integration.latency"
      "integration-requestId"     = "$context.integration.requestId"
      "integration-integrationStatus" = "$context.integration.integrationStatus"
      "response-latency"          = "$context.responseLatency"
      status                      = "$context.status"
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








