# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "schema_arn" {
  description = "ARN of the PublicationEvaluationCompleted schema"
  value       = aws_schemas_schema.publication_evaluation_completed.arn
}

output "schema_name" {
  description = "Name of the PublicationEvaluationCompleted schema"
  value       = aws_schemas_schema.publication_evaluation_completed.name
}
