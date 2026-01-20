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

data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name = "/uni-prop/UnicornApprovalsNamespace"
}

data "aws_ssm_parameter" "unicorn_web_namespace" {
  name = "/uni-prop/UnicornWebNamespace"
}

data "aws_ssm_parameter" "web_event_bus" {
  name = "/uni-prop/${var.stage}/WebEventBus"
}

data "aws_ssm_parameter" "approvals_event_bus_arn" {
  name = "/uni-prop/${var.stage}/ApprovalsEventBusArn"
}

data "aws_ssm_parameter" "approvals_eventbridge_role_arn" {
  name = "/uni-prop/${var.stage}/ApprovalsEventBridgeRoleArn"
}

locals {
  common_tags = {
    stage                        = var.stage
    rule_owner_service_namespace = data.aws_ssm_parameter.unicorn_approvals_namespace.value
  }
}

resource "aws_cloudwatch_event_rule" "publication_approval_requested_subscription" {
  name           = "${data.aws_ssm_parameter.unicorn_approvals_namespace.value}-PublicationApprovalRequested"
  description    = "Subscription rule for the PublicationApprovalRequested events from the Unicorn Web service and forwards them to the Unicorn Approvals event bus, triggering the Approval workflow."
  event_bus_name = data.aws_ssm_parameter.web_event_bus.value
  state          = "ENABLED"

  event_pattern = jsonencode({
    source      = [data.aws_ssm_parameter.unicorn_web_namespace.value]
    "detail-type" = ["PublicationApprovalRequested"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "publication_approval_requested_subscription" {
  rule           = aws_cloudwatch_event_rule.publication_approval_requested_subscription.name
  event_bus_name = data.aws_ssm_parameter.web_event_bus.value
  target_id      = "SendEventTo"
  arn            = data.aws_ssm_parameter.approvals_event_bus_arn.value
  role_arn       = data.aws_ssm_parameter.approvals_eventbridge_role_arn.value
}








