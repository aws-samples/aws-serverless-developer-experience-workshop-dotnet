# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Unicorn Approvals domain root (deployment phase 3: domains).
#
# Owns the Approvals event bus and its resource policy, event bus logging, the
# EventBridge forwarding role that consumer subscription roots use to deliver
# events to this bus, and the Approvals schema registry. Other roots discover these
# resources only through the SSM parameters published at the end of this file.
#
# Reads:     /uni-prop/UnicornApprovalsNamespace (Shared namespaces root)
# Publishes: /uni-prop/<stage>/ApprovalsEventBus, ApprovalsEventBusArn,
#            ApprovalsSchemaRegistryName, ApprovalsEventBridgeRoleArn

#################################################################################################
#### DATA SOURCES
#################################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name = "/uni-prop/UnicornApprovalsNamespace"
}

#################################################################################################
#### EVENT BUS
#################################################################################################

resource "aws_cloudwatch_event_bus" "approvals_event_bus" {
  name = local.event_bus_name

  log_config {
    include_detail = "FULL"
    level          = local.log_level
  }
}

# Principals in this account may publish only events whose source is the Approvals
# namespace, and may manage only rules that filter on that source.
# `$${aws:PrincipalAccount}` escapes Terraform interpolation so IAM receives the
# literal policy variable.
data "aws_iam_policy_document" "approvals_event_bus_policy" {
  statement {
    sid       = "OnlyApprovalsServiceCanPublishToEventBus-${var.stage}"
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.approvals_event_bus.arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "events:source"
      values   = [local.unicorn_approvals_namespace]
    }
  }

  statement {
    sid    = "OnlyRulesForApprovalsServiceEvents-${var.stage}"
    effect = "Allow"
    actions = [
      "events:PutRule",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:DisableRule",
      "events:EnableRule",
      "events:PutTargets",
      "events:RemoveTargets"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:rule/${aws_cloudwatch_event_bus.approvals_event_bus.name}/*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "events:creatorAccount"
      values   = ["$${aws:PrincipalAccount}"]
    }

    condition {
      test     = "StringEquals"
      variable = "events:source"
      values   = [local.unicorn_approvals_namespace]
    }

    condition {
      test     = "Null"
      variable = "events:source"
      values   = ["false"]
    }
  }
}

resource "aws_cloudwatch_event_bus_policy" "approvals_event_bus_policy" {
  event_bus_name = aws_cloudwatch_event_bus.approvals_event_bus.name
  policy         = data.aws_iam_policy_document.approvals_event_bus_policy.json
}

#################################################################################################
#### EVENT BUS LOGGING (INFO and ERROR logs delivered to CloudWatch Logs)
#################################################################################################

resource "aws_cloudwatch_log_group" "event_bus_log_group" {
  name              = "/aws/vendedlogs/events/event-bus/${aws_cloudwatch_event_bus.approvals_event_bus.name}-${var.stage}"
  retention_in_days = local.logs_retention_days
}

resource "aws_cloudwatch_log_delivery_source" "event_bus_error_delivery_source" {
  name         = "${aws_cloudwatch_event_bus.approvals_event_bus.name}-ERROR-LOGS-${var.stage}"
  log_type     = "ERROR_LOGS"
  resource_arn = aws_cloudwatch_event_bus.approvals_event_bus.arn
}

resource "aws_cloudwatch_log_delivery_source" "event_bus_info_delivery_source" {
  name         = "${aws_cloudwatch_event_bus.approvals_event_bus.name}-INFO-LOGS-${var.stage}"
  log_type     = "INFO_LOGS"
  resource_arn = aws_cloudwatch_event_bus.approvals_event_bus.arn
}

resource "aws_cloudwatch_log_delivery_destination" "event_bus_delivery_destination" {
  name = "${aws_cloudwatch_event_bus.approvals_event_bus.name}-DeliveryDestination-${var.stage}"
  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.event_bus_log_group.arn
  }
}

resource "aws_cloudwatch_log_delivery" "event_bus_info_logging_delivery" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.event_bus_info_delivery_source.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.event_bus_delivery_destination.arn
}

# Created after the INFO delivery so the two deliveries to the shared
# destination are never created concurrently.
resource "aws_cloudwatch_log_delivery" "event_bus_error_logging_delivery" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.event_bus_error_delivery_source.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.event_bus_delivery_destination.arn

  depends_on = [aws_cloudwatch_log_delivery.event_bus_info_logging_delivery]
}

#################################################################################################
#### EVENTBRIDGE FORWARDING ROLE (assumed by subscription rules that target this bus)
#################################################################################################

resource "aws_iam_role" "approvals_eventbridge_role" {
  name = "uni-prop-${var.stage}-approvals-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "approvals_eventbridge_role_policy" {
  name = "PutEventsOnApprovalsEventBus"
  role = aws_iam_role.approvals_eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = aws_cloudwatch_event_bus.approvals_event_bus.arn
      }
    ]
  })
}

#################################################################################################
#### SCHEMA REGISTRY
#################################################################################################

resource "aws_schemas_registry" "approvals_schema_registry" {
  name        = local.registry_name
  description = "Event schemas for Unicorn Approvals"
}

resource "aws_schemas_registry_policy" "event_registry_policy" {
  registry_name = aws_schemas_registry.approvals_schema_registry.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowExternalServices"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.account_id
        }
        Action = [
          "schemas:DescribeCodeBinding",
          "schemas:DescribeRegistry",
          "schemas:DescribeSchema",
          "schemas:GetCodeBindingSource",
          "schemas:ListSchemas",
          "schemas:ListSchemaVersions",
          "schemas:SearchSchemas"
        ]
        Resource = [
          aws_schemas_registry.approvals_schema_registry.arn,
          "arn:${data.aws_partition.current.partition}:schemas:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:schema/${aws_schemas_registry.approvals_schema_registry.name}*"
        ]
      }
    ]
  })
}

#################################################################################################
#### SSM OPERATIONAL CONTRACTS (consumed by schema, service, and subscription roots)
#################################################################################################

resource "aws_ssm_parameter" "approvals_event_bus_name" {
  name  = "/uni-prop/${var.stage}/ApprovalsEventBus"
  type  = "String"
  value = aws_cloudwatch_event_bus.approvals_event_bus.name
}

resource "aws_ssm_parameter" "approvals_event_bus_arn" {
  name  = "/uni-prop/${var.stage}/ApprovalsEventBusArn"
  type  = "String"
  value = aws_cloudwatch_event_bus.approvals_event_bus.arn
}

resource "aws_ssm_parameter" "approvals_schema_registry_name" {
  name  = "/uni-prop/${var.stage}/ApprovalsSchemaRegistryName"
  type  = "String"
  value = aws_schemas_registry.approvals_schema_registry.name
}

resource "aws_ssm_parameter" "approvals_eventbridge_role_arn" {
  name  = "/uni-prop/${var.stage}/ApprovalsEventBridgeRoleArn"
  type  = "String"
  value = aws_iam_role.approvals_eventbridge_role.arn
}
