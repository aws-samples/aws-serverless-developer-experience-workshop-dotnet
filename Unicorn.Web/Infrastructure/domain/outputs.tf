output "web_event_bus_name" {
  description = "Name of the Unicorn Web Event Bus"
  value       = aws_cloudwatch_event_bus.web_event_bus.name
}

output "web_event_bus_arn" {
  description = "ARN of the Unicorn Web Event Bus"
  value       = aws_cloudwatch_event_bus.web_event_bus.arn
}

output "web_event_handler_function_log_group_name" {
  description = "Name of the Web Event Handler Function Log Group"
  value       = aws_cloudwatch_log_group.event_bus_log_group.name
}

output "web_event_handler_function_log_group_arn" {
  description = "ARN of the Web Event Handler Function Log Group"
  value       = aws_cloudwatch_log_group.event_bus_log_group.arn
}

output "web_schema_registry_name" {
  description = "Name of the Unicorn Web Schema Registry"
  value       = aws_schemas_registry.web_schema_registry.name
}

output "web_schema_registry_arn" {
  description = "ARN of the Unicorn Web Schema Registry"
  value       = aws_schemas_registry.web_schema_registry.arn
}

output "web_eventbridge_role_arn" {
  description = "ARN of the Unicorn Web EventBridge Role"
  value       = aws_iam_role.web_eventbridge_role.arn
}








