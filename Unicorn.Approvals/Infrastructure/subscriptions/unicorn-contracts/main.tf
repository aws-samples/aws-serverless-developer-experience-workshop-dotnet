# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Approvals-owned subscription to Contracts events (deployment phase 5: subscriptions).
#
# Creates a rule on the Contracts event bus that forwards ContractStatusChanged events to
# the Approvals event bus. The consumer owns the rule so it can change what it
# subscribes to without editing the Contracts domain. The rule is tagged with
# its owner, and the target assumes the consumer's EventBridge forwarding role.
#
# Reads: /uni-prop/{UnicornApprovalsNamespace, UnicornContractsNamespace}
#        /uni-prop/<stage>/{ContractsEventBusArn, ApprovalsEventBusArn, ApprovalsEventBridgeRoleArn}

#################################################################################################
#### DATA SOURCES (SSM operational contracts)
#################################################################################################

data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name = "/uni-prop/UnicornApprovalsNamespace"
}

data "aws_ssm_parameter" "unicorn_contracts_namespace" {
  name = "/uni-prop/UnicornContractsNamespace"
}

data "aws_ssm_parameter" "contracts_event_bus_arn" {
  name = "/uni-prop/${var.stage}/ContractsEventBusArn"
}

data "aws_ssm_parameter" "approvals_event_bus_arn" {
  name = "/uni-prop/${var.stage}/ApprovalsEventBusArn"
}

data "aws_ssm_parameter" "approvals_eventbridge_role_arn" {
  name = "/uni-prop/${var.stage}/ApprovalsEventBridgeRoleArn"
}

#################################################################################################
#### SUBSCRIPTION RULE AND TARGET
#################################################################################################

resource "aws_cloudwatch_event_rule" "contract_status_changed_subscription" {
  name           = "${local.unicorn_approvals_namespace}-ContractStatusChanged"
  description    = "Subscription rule for ContractStatusChanged event targeting the Unicorn Approvals event bus for processing approval workflows."
  event_bus_name = local.contracts_event_bus_arn

  event_pattern = jsonencode({
    source      = [local.unicorn_contracts_namespace]
    detail-type = ["ContractStatusChanged"]
  })

  tags = {
    "rule-owner-service-namespace" = local.unicorn_approvals_namespace
  }
}

# The SAM subscription template defines no DLQ for this cross-bus target, and
# retry and dead-letter behavior is a must-match parity surface (PARITY.md).
# tflint-ignore: aws_cloudwatch_event_target_no_dlq
resource "aws_cloudwatch_event_target" "contract_status_changed_subscription" {
  rule           = aws_cloudwatch_event_rule.contract_status_changed_subscription.name
  event_bus_name = local.contracts_event_bus_arn
  target_id      = "SendEventTo"
  arn            = local.approvals_event_bus_arn
  role_arn       = local.approvals_eventbridge_role_arn
}
