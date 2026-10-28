# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# PublicationEvaluationCompleted event schema (deployment phase 4: schemas, before workloads).
#
# Registers the OpenAPI 3 schema for PublicationEvaluationCompleted events, published by
# the approval state machine when a publication evaluation finishes.
# The schema document lives in locals.tf. Its property names and casing are a
# must-match parity surface; scripts/validate_infrastructure.py checks the
# required properties.
#
# Reads: /uni-prop/UnicornApprovalsNamespace, /uni-prop/<stage>/ApprovalsSchemaRegistryName

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
