locals {
  # SSM parameter values are marked sensitive by the AWS provider; the namespace
  # values are public workshop constants, so unwrap them for use in names/outputs.
  unicorn_contracts_namespace = nonsensitive(data.aws_ssm_parameter.unicorn_contracts_namespace.value)
  schema_name                 = "${local.unicorn_contracts_namespace}@ContractStatusChanged"
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
          type                          = "object"
          required                      = ["detail-type", "resources", "detail", "id", "source", "time", "region", "version", "account"]
          "x-amazon-events-detail-type" = "ContractStatusChanged"
          "x-amazon-events-source"      = local.unicorn_contracts_namespace
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
              type = "array"
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
          required = ["PropertyId", "ContractId", "ContractStatus", "ContractLastModifiedOn"]
          properties = {
            PropertyId = {
              type = "string"
            }
            ContractId = {
              type   = "string"
              format = "uuid"
            }
            ContractStatus = {
              type = "string"
            }
            ContractLastModifiedOn = {
              type   = "string"
              format = "date-time"
            }
          }
        }
      }
    }
  })
}
