terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_ssm_parameter" "unicorn_contracts_namespace" {
  name = "/uni-prop/UnicornContractsNamespace"
}

data "aws_ssm_parameter" "contracts_schema_registry_name" {
  name = "/uni-prop/${var.stage}/ContractsSchemaRegistryName"
}

locals {
  schema_name = "${data.aws_ssm_parameter.unicorn_contracts_namespace.value}@ContractStatusChanged"
  schema_content = jsonencode({
    openapi = "3.0.0"
    info = {
      version = "2.0.0"
      title   = "ContractStatusChanged"
    }
    paths = {}
    components = {
      schemas = {
        AWSEvent = {
          type     = "object"
          required = ["detail-type", "resources", "detail", "id", "source", "time", "region", "version", "account"]
          "x-amazon-events-detail-type" = "ContractStatusChanged"
          "x-amazon-events-source"       = data.aws_ssm_parameter.unicorn_contracts_namespace.value
          properties = {
            detail = {
              "$ref" = "#/components/schemas/ContractStatusChanged"
            }
            account = {
              type = "string"
            }
            "detail-type" = {
              type = "string"
            }
            id = {
              type = "string"
            }
            region = {
              type = "string"
            }
            resources = {
              type  = "array"
              items = {
                type = "object"
              }
            }
            source = {
              type = "string"
            }
            time = {
              type   = "string"
              format = "date-time"
            }
            version = {
              type = "string"
            }
          }
        }
        ContractStatusChanged = {
          type     = "object"
          required = ["contract_last_modified_on", "contract_last_modified_by", "contract_id", "contract_status", "property_id"]
          properties = {
            contract_id = {
              type = "string"
            }
            contract_last_modified_by = {
              type = "string"
            }
            contract_last_modified_on = {
              type   = "string"
              format = "date-time"
            }
            contract_status = {
              type = "string"
            }
            property_id = {
              type = "string"
            }
          }
        }
      }
    }
  })
}

resource "aws_schemas_schema" "contract_status_changed" {
  name        = local.schema_name
  registry_name = data.aws_ssm_parameter.contracts_schema_registry_name.value
  type        = "OpenApi3"
  description = "EventBridge schema for ContractStatusChanged events published by the Unicorn Contracts Service when a contract is updated."
  content     = local.schema_content
}








