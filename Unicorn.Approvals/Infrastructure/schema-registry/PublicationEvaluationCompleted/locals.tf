# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  # SSM parameter values are marked sensitive by the AWS provider; the namespace
  # values are public workshop constants, so unwrap them for use in names/outputs.
  unicorn_approvals_namespace = nonsensitive(data.aws_ssm_parameter.unicorn_approvals_namespace.value)
  schema_name                 = "${local.unicorn_approvals_namespace}@PublicationEvaluationCompleted"

  # AWSEvent describes the EventBridge envelope; the detail object is the
  # PublicationEvaluationCompleted payload that consumers deserialize.
  schema_content = jsonencode({
    openapi = "3.0.0"
    info = {
      version = "1.0.0"
      title   = "PublicationEvaluationCompleted"
    }
    paths = {}
    components = {
      schemas = {
        AWSEvent = {
          type                          = "object"
          required                      = ["detail-type", "resources", "detail", "id", "source", "time", "region", "version", "account"]
          "x-amazon-events-detail-type" = "PublicationEvaluationCompleted"
          "x-amazon-events-source"      = local.unicorn_approvals_namespace
          properties = {
            detail = {
              "$ref" = "#/components/schemas/PublicationEvaluationCompleted"
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
        PublicationEvaluationCompleted = {
          type     = "object"
          required = ["PropertyId", "EvaluationResult"]
          properties = {
            PropertyId = {
              type = "string"
            }
            EvaluationResult = {
              type = "string"
            }
          }
        }
      }
    }
  })
}
