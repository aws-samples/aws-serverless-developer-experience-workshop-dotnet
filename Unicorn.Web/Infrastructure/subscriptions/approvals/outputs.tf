# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "publication_evaluation_completed_subscription_arn" {
  description = "Rule ARN for Approvals service event subscription"
  value       = aws_cloudwatch_event_rule.publication_evaluation_completed_subscription.arn
}
