output "base_url" {
  description = "Web service API endpoint"
  value       = "https://${aws_api_gateway_rest_api.unicorn_contracts_api.id}.execute-api.${data.aws_region.current.id}.amazonaws.com"
}

output "api_url" {
  description = "Contract service API endpoint"
  value       = "https://${aws_api_gateway_rest_api.unicorn_contracts_api.id}.execute-api.${data.aws_region.current.id}.amazonaws.com/${var.stage}/"
}

output "ingest_queue_url" {
  description = "URL for the Ingest SQS Queue"
  value       = aws_sqs_queue.unicorn_contracts_ingest_queue.url
}

output "contracts_table_name" {
  description = "DynamoDB table storing contract information"
  value       = aws_dynamodb_table.contracts_table.name
}

output "contract_event_handler_function_name" {
  description = "ContractEventHandler function name"
  value       = aws_lambda_function.contract_event_handler.function_name
}

output "contract_event_handler_function_arn" {
  description = "ContractEventHandler function ARN"
  value       = aws_lambda_function.contract_event_handler.arn
}

output "unicorn_contracts_catch_all_log_group_arn" {
  description = "Log all events on the service's EventBridge Bus"
  value       = aws_cloudwatch_log_group.unicorn_contracts_catch_all.arn
}








