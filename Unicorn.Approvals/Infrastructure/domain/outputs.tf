output "approvals_event_bus_name" {
  description = "Name of the Unicorn Approvals Event Bus"
  value       = aws_cloudwatch_event_bus.approvals_event_bus.name
}

output "approvals_event_bus_arn" {
  description = "ARN of the Unicorn Approvals Event Bus"
  value       = aws_cloudwatch_event_bus.approvals_event_bus.arn
}

output "event_bus_log_group_name" {
  description = "Name of the Approvals Event Bus Log Group"
  value       = aws_cloudwatch_log_group.event_bus_log_group.name
}

output "event_bus_log_group_arn" {
  description = "ARN of the Approvals Event Bus Log Group"
  value       = aws_cloudwatch_log_group.event_bus_log_group.arn
}

output "schema_registry_name" {
  description = "Name of the Unicorn Approvals Schema Registry"
  value       = aws_schemas_registry.approvals_schema_registry.name
  sensitive   = true
}

output "schema_registry_arn" {
  description = "ARN of the Unicorn Approvals Schema Registry"
  value       = aws_schemas_registry.approvals_schema_registry.arn
}

output "approvals_eventbridge_role_arn" {
  description = "ARN of the Unicorn Approvals EventBridge Role"
  value       = aws_iam_role.approvals_eventbridge_role.arn
}
