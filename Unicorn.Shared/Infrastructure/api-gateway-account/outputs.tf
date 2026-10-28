# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "cloudwatch_role_arn" {
  description = "IAM role used by API Gateway to publish CloudWatch Logs."
  value       = aws_iam_role.api_gateway_cloudwatch_logs.arn
}
