data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name = "/uni-prop/UnicornApprovalsNamespace"
}

data "aws_ssm_parameter" "approvals_schema_registry_name" {
  name = "/uni-prop/${var.stage}/ApprovalsSchemaRegistryName"
}

resource "aws_schemas_schema" "publication_evaluation_completed" {
  name          = local.schema_name
  registry_name = data.aws_ssm_parameter.approvals_schema_registry_name.value
  type          = "OpenApi3"
  description   = "EventBridge schema for PublicationEvaluationCompleted events published by the Unicorn Approvals Service when a property publication evaluation is completed."
  content       = local.schema_content
}
