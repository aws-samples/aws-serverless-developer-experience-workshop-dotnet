# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# PublicationApprovalRequested event schema (deployment phase 4: schemas, before workloads).
#
# Registers the OpenAPI 3 schema for PublicationApprovalRequested events, published by
# the request approval function when a property publication is requested.
# The schema document lives in locals.tf. Its property names and casing are a
# must-match parity surface; scripts/validate_infrastructure.py checks the
# required properties.
#
# Reads: /uni-prop/UnicornWebNamespace, /uni-prop/<stage>/WebSchemaRegistryName

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
