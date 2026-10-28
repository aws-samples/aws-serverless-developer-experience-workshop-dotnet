# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  # SSM parameter values are marked sensitive by the AWS provider; the namespace
  # values are public workshop constants, so unwrap them for use in names/outputs.
  unicorn_web_namespace = nonsensitive(data.aws_ssm_parameter.unicorn_web_namespace.value)
  schema_name           = "${local.unicorn_web_namespace}@PublicationApprovalRequested"

  # AWSEvent describes the EventBridge envelope; the detail object is the
  # PublicationApprovalRequested payload that consumers deserialize.
  schema_content = jsonencode({
    openapi = "3.0.0"
    info = {
      version = "1.0.0"
      title   = "PublicationApprovalRequested"
    }
    paths = {}
    components = {
      schemas = {
        AWSEvent = {
          type                          = "object"
          required                      = ["detail-type", "resources", "detail", "id", "source", "time", "region", "version", "account"]
          "x-amazon-events-detail-type" = "PublicationApprovalRequested"
          "x-amazon-events-source"      = local.unicorn_web_namespace
          properties = {
            detail = {
              "$ref" = "#/components/schemas/PublicationApprovalRequested"
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
                type = "string"
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
        PublicationApprovalRequested = {
          type     = "object"
          required = ["PropertyId", "Status", "Description", "Images", "Address"]
          properties = {
            PropertyId = {
              type = "string"
            }
            Status = {
              type = "string"
            }
            Description = {
              type = "string"
            }
            Images = {
              type = "array"
              items = {
                type = "string"
              }
            }
            Address = {
              "$ref" = "#/components/schemas/Address"
            }
          }
        }
        Address = {
          type     = "object"
          required = ["Country", "City", "Street", "Number"]
          properties = {
            Country = {
              type = "string"
            }
            City = {
              type = "string"
            }
            Street = {
              type = "string"
            }
            Number = {
              type = "string"
            }
          }
        }
      }
    }
  })
}
