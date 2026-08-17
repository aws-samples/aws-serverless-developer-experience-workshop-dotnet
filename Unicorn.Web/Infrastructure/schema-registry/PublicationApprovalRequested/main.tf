data "aws_ssm_parameter" "unicorn_web_namespace" {
  name = "/uni-prop/UnicornWebNamespace"
}

data "aws_ssm_parameter" "web_schema_registry_name" {
  name = "/uni-prop/${var.stage}/WebSchemaRegistryName"
}

resource "aws_schemas_schema" "publication_approval_requested" {
  name          = local.schema_name
  registry_name = data.aws_ssm_parameter.web_schema_registry_name.value
  type          = "OpenApi3"
  description   = "EventBridge schema for PublicationApprovalRequested events published by the Unicorn Web Service when a property publication approval is requested."
  content       = local.schema_content
}
