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

data "aws_ssm_parameter" "unicorn_contracts_namespace" {
  name = "/uni-prop/UnicornContractsNamespace"
}

data "aws_ssm_parameter" "contracts_event_bus" {
  name = "/uni-prop/${var.stage}/ContractsEventBus"
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

resource "aws_cloudwatch_event_rule" "contract_status_changed_subscription" {
  name           = "${data.aws_ssm_parameter.unicorn_approvals_namespace.value}-ContractStatusChanged"
  description    = "Subscription rule for ContractStatusChanged event targeting the Unicorn Approvals event bus for processing approval workflows."
  event_bus_name = data.aws_ssm_parameter.contracts_event_bus.value
  state          = "ENABLED"

  event_pattern = jsonencode({
    source      = [data.aws_ssm_parameter.unicorn_contracts_namespace.value]
    "detail-type" = ["ContractStatusChanged"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "contract_status_changed_subscription" {
  rule           = aws_cloudwatch_event_rule.contract_status_changed_subscription.name
  event_bus_name = data.aws_ssm_parameter.contracts_event_bus.value
  target_id      = "SendEventTo"
  arn            = data.aws_ssm_parameter.approvals_event_bus_arn.value
  role_arn       = data.aws_ssm_parameter.approvals_eventbridge_role_arn.value
}








