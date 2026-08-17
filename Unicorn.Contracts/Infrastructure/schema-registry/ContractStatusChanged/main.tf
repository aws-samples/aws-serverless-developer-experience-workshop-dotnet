data "aws_ssm_parameter" "unicorn_contracts_namespace" {
  name = "/uni-prop/UnicornContractsNamespace"
}

data "aws_ssm_parameter" "contracts_schema_registry_name" {
  name = "/uni-prop/${var.stage}/ContractsSchemaRegistryName"
}

resource "aws_schemas_schema" "contract_status_changed" {
  name          = local.schema_name
  registry_name = data.aws_ssm_parameter.contracts_schema_registry_name.value
  type          = "OpenApi3"
  description   = "EventBridge schema for ContractStatusChanged events published by the Unicorn Contracts Service when a contract is updated."
  content       = local.schema_content
}
