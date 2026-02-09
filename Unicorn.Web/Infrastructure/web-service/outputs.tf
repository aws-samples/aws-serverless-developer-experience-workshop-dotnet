output "base_url" {
  description = "Web service API endpoint"
  value       = "https://${aws_api_gateway_rest_api.unicorn_web_api.id}.execute-api.${data.aws_region.current.id}.amazonaws.com"
}

output "api_url" {
  description = "Web service API endpoint"
  value       = "https://${aws_api_gateway_rest_api.unicorn_web_api.id}.execute-api.${data.aws_region.current.id}.amazonaws.com/${var.stage}/"
}

output "ingest_queue_url" {
  description = "URL for the Ingest SQS Queue"
  value       = aws_sqs_queue.unicorn_web_ingest_queue.url
}

output "properties_table_name" {
  description = "Name of the DynamoDB Table for Unicorn Web"
  value       = aws_dynamodb_table.properties_table.name
}

output "search_function_arn" {
  description = "Search function ARN"
  value       = aws_lambda_function.search_function.arn
}

output "request_approval_function_arn" {
  description = "Request approval function ARN"
  value       = aws_lambda_function.request_approval_function.arn
}

output "publication_evaluation_event_handler_function_arn" {
  description = "Publication evaluation event handler function ARN"
  value       = aws_lambda_function.publication_evaluation_event_handler.arn
}

output "unicorn_web_catch_all_log_group_arn" {
  description = "Log all events on the service's EventBridge Bus"
  value       = aws_cloudwatch_log_group.unicorn_web_catch_all.arn
}
