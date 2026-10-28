# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ContractStatusChanged event schema (deployment phase 4: schemas, before workloads).
#
# Registers the OpenAPI 3 schema for ContractStatusChanged events, published by
# the Contracts table stream pipe when a contract is created or its status changes.
# The schema document lives in locals.tf. Its property names and casing are a
# must-match parity surface; scripts/validate_infrastructure.py checks the
# required properties.
#
# Reads: /uni-prop/UnicornContractsNamespace, /uni-prop/<stage>/ContractsSchemaRegistryName

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
