output "schema_arn" {
  description = "ARN of the PublicationApprovalRequested schema"
  value       = aws_schemas_schema.publication_approval_requested.arn
}

output "schema_name" {
  description = "Name of the PublicationApprovalRequested schema"
  value       = aws_schemas_schema.publication_approval_requested.name
}
