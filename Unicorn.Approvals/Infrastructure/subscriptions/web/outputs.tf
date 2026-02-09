output "publication_approval_requested_subscription_arn" {
  description = "Rule ARN for Web service event subscription"
  value       = aws_cloudwatch_event_rule.publication_approval_requested_subscription.arn
}
