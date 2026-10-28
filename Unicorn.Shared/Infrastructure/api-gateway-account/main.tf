# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# API Gateway account settings for this account and Region (deployment phase 2: shared).
#
# aws_api_gateway_account is an account/Region singleton, so this root is its only
# owner; scripts/validate_infrastructure.py enforces that. The Contracts and Web
# stage method settings need this CloudWatch Logs role for execution logging.
# make delete-all deliberately preserves this root.

data "aws_partition" "current" {}

resource "aws_iam_role" "api_gateway_cloudwatch_logs" {
  name = "uni-prop-${var.region}-api-gateway-cloudwatch-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs" {
  role       = aws_iam_role.api_gateway_cloudwatch_logs.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_logs.arn
}
