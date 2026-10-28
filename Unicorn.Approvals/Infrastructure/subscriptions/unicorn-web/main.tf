# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Approvals-owned subscription to Web events (deployment phase 5: subscriptions).
#
# Creates a rule on the Web event bus that forwards PublicationApprovalRequested events to
# the Approvals event bus. The consumer owns the rule so it can change what it
# subscribes to without editing the Web domain. The rule is tagged with
# its owner, and the target assumes the consumer's EventBridge forwarding role.
#
# Reads: /uni-prop/{UnicornApprovalsNamespace, UnicornWebNamespace}
#        /uni-prop/<stage>/{WebEventBusArn, ApprovalsEventBusArn, ApprovalsEventBridgeRoleArn}

#################################################################################################
#### DATA SOURCES (SSM operational contracts)
#################################################################################################

data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name = "/uni-prop/UnicornApprovalsNamespace"
}

data "aws_ssm_parameter" "unicorn_web_namespace" {
  name = "/uni-prop/UnicornWebNamespace"
}

data "aws_ssm_parameter" "web_event_bus_arn" {
  name = "/uni-prop/${var.stage}/WebEventBusArn"
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

resource "aws_cloudwatch_event_rule" "publication_approval_requested_subscription" {
  name           = "${local.unicorn_approvals_namespace}-PublicationApprovalRequested"
  description    = "Subscription rule for PublicationApprovalRequested events from the Unicorn Web service, triggering the Approval workflow."
  event_bus_name = local.web_event_bus_arn

  event_pattern = jsonencode({
    source      = [local.unicorn_web_namespace]
    detail-type = ["PublicationApprovalRequested"]
  })

  tags = {
    "rule-owner-service-namespace" = local.unicorn_approvals_namespace
  }
}

# The SAM subscription template defines no DLQ for this cross-bus target, and
# retry and dead-letter behavior is a must-match parity surface (PARITY.md).
# tflint-ignore: aws_cloudwatch_event_target_no_dlq
resource "aws_cloudwatch_event_target" "publication_approval_requested_subscription" {
  rule           = aws_cloudwatch_event_rule.publication_approval_requested_subscription.name
  event_bus_name = local.web_event_bus_arn
  target_id      = "SendEventTo"
  arn            = local.approvals_event_bus_arn
  role_arn       = local.approvals_eventbridge_role_arn
}
