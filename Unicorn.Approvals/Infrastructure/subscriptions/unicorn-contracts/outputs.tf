output "contract_status_changed_subscription" {
  description = "Rule ARN for Contract service event subscription"
  value       = aws_cloudwatch_event_rule.contract_status_changed_subscription.arn
}








