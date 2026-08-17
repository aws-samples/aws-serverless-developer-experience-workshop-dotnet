output "contracts_event_bus_name" {
  description = "Name of the Unicorn Contracts Event Bus"
  value       = aws_cloudwatch_event_bus.contracts_event_bus.name
}

output "contracts_event_bus_arn" {
  description = "ARN of the Unicorn Contracts Event Bus"
  value       = aws_cloudwatch_event_bus.contracts_event_bus.arn
}

output "event_handler_function_log_group_name" {
  description = "Name of the Contracts Event Handler Function Log Group"
  value       = aws_cloudwatch_log_group.event_handler_function_log_group.name
}

output "event_handler_function_log_group_arn" {
  description = "ARN of the Contracts Event Handler Function Log Group"
  value       = aws_cloudwatch_log_group.event_handler_function_log_group.arn
}

output "schema_registry_name" {
  description = "Name of the Unicorn Contracts Schema Registry"
  value       = aws_schemas_registry.contracts_schema_registry.name
  sensitive   = true
}

output "schema_registry_arn" {
  description = "ARN of the Unicorn Contracts Schema Registry"
  value       = aws_schemas_registry.contracts_schema_registry.arn
}

output "contracts_eventbridge_role_arn" {
  description = "ARN of the Unicorn Contracts EventBridge Role"
  value       = aws_iam_role.contracts_eventbridge_role.arn
}








