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

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_ssm_parameter" "unicorn_web_namespace" {
  name = "/uni-prop/UnicornWebNamespace"
}

locals {
  event_bus_name      = "unicorn-web-eventbus-${var.stage}"
  registry_name       = "${data.aws_ssm_parameter.unicorn_web_namespace.value}-${var.stage}"
  logs_retention_days = var.stage == "prod" ? 14 : 3
  is_prod            = var.stage == "prod"
  log_level          = var.stage == "prod" ? "ERROR" : "INFO"
  common_tags = {
    stage     = var.stage
    project   = "AWS Serverless Developer Experience"
    namespace = data.aws_ssm_parameter.unicorn_web_namespace.value
  }
}

resource "aws_cloudwatch_event_bus" "web_event_bus" {
  name = local.event_bus_name

  log_config {
    include_detail = "FULL"
    level          = local.log_level
  }

  tags = local.common_tags
}

resource "aws_ssm_parameter" "web_event_bus_name" {
  name  = "/uni-prop/${var.stage}/WebEventBus"
  type  = "String"
  value = aws_cloudwatch_event_bus.web_event_bus.name
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "web_event_bus_arn" {
  name  = "/uni-prop/${var.stage}/WebEventBusArn"
  type  = "String"
  value = aws_cloudwatch_event_bus.web_event_bus.arn
  tags  = local.common_tags
}

resource "aws_cloudwatch_event_bus_policy" "web_event_bus_publish_policy" {
  event_bus_name = aws_cloudwatch_event_bus.web_event_bus.name
  statement_id   = "OnlyWebServiceCanPublishToEventBus-${var.stage}"

  statement = jsonencode({
    Effect = "Allow"
    Principal = {
      AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
    }
    Action   = "events:PutEvents"
    Resource = aws_cloudwatch_event_bus.web_event_bus.arn
    Condition = {
      StringEquals = {
        "events:source" = [data.aws_ssm_parameter.unicorn_web_namespace.value]
      }
    }
  })
}

resource "aws_cloudwatch_event_bus_policy" "rule_management_policy" {
  event_bus_name = aws_cloudwatch_event_bus.web_event_bus.name
  statement_id   = "OnlyRulesForWebServiceEvents-${var.stage}"

  statement = jsonencode({
    Effect = "Allow"
    Principal = {
      AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
    }
    Action = [
      "events:PutRule",
      "events:DeleteRule",
      "events:DescribeRule",
      "events:DisableRule",
      "events:EnableRule",
      "events:PutTargets",
      "events:RemoveTargets"
    ]
    Resource = "arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:rule/${aws_cloudwatch_event_bus.web_event_bus.name}/*"
    Condition = {
      StringEqualsIfExists = {
        "events:creatorAccount" = "${data.aws_caller_identity.current.account_id}"
      }
      StringEquals = {
        "events:source" = [data.aws_ssm_parameter.unicorn_web_namespace.value]
      }
      Null = {
        "events:source" = "false"
      }
    }
  })
}

resource "aws_iam_role" "web_eventbridge_role" {
  name = "uni-prop-${var.stage}-web-eventbridge-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy" "web_eventbridge_role_policy" {
  name = "PutEventsOnWebEventBus"
  role = aws_iam_role.web_eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = aws_cloudwatch_event_bus.web_event_bus.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "event_bus_log_group" {
  name              = "/aws/vendedlogs/events/event-bus/${aws_cloudwatch_event_bus.web_event_bus.name}-${var.stage}"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_delivery_source" "event_bus_error_delivery_source" {
  name        = "${aws_cloudwatch_event_bus.web_event_bus.name}-ERROR-LOGS-${var.stage}"
  log_type    = "ERROR_LOGS"
  resource_arn = aws_cloudwatch_event_bus.web_event_bus.arn
}

resource "aws_cloudwatch_log_delivery_source" "event_bus_info_delivery_source" {
  name        = "${aws_cloudwatch_event_bus.web_event_bus.name}-INFO-LOGS-${var.stage}"
  log_type    = "INFO_LOGS"
  resource_arn = aws_cloudwatch_event_bus.web_event_bus.arn
}

resource "aws_cloudwatch_log_delivery_destination" "event_bus_delivery_destination" {
  name                  = "${aws_cloudwatch_event_bus.web_event_bus.name}-DeliveryDestination-${var.stage}"
  destination_resource_arn = aws_cloudwatch_log_group.event_bus_log_group.arn
}

resource "aws_cloudwatch_log_delivery" "event_bus_info_logging_delivery" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.event_bus_info_delivery_source.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.event_bus_delivery_destination.arn
}

resource "aws_cloudwatch_log_delivery" "event_bus_error_logging_delivery" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.event_bus_error_delivery_source.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.event_bus_delivery_destination.arn

  depends_on = [aws_cloudwatch_log_delivery.event_bus_info_logging_delivery]
}

resource "aws_schemas_registry" "web_schema_registry" {
  name        = local.registry_name
  description = "Event schemas for Unicorn Web"
  tags        = local.common_tags
}

resource "aws_ssm_parameter" "web_schema_registry_name" {
  name  = "/uni-prop/${var.stage}/WebSchemaRegistryName"
  type  = "String"
  value = aws_schemas_registry.web_schema_registry.name
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "web_eventbridge_role_arn" {
  name  = "/uni-prop/${var.stage}/WebEventBridgeRoleArn"
  type  = "String"
  value = aws_iam_role.web_eventbridge_role.arn
  tags  = local.common_tags
}

resource "aws_schemas_registry_policy" "event_registry_policy" {
  registry_name = aws_schemas_registry.web_schema_registry.name

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
          aws_schemas_registry.web_schema_registry.arn,
          "arn:${data.aws_partition.current.partition}:schemas:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:schema/${aws_schemas_registry.web_schema_registry.name}*"
        ]
      }
    ]
  })
}








