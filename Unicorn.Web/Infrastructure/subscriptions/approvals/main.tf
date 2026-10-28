# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Web-owned subscription to Approvals events (deployment phase 5: subscriptions).
#
# Creates a rule on the Approvals event bus that forwards PublicationEvaluationCompleted events to
# the Web event bus. The consumer owns the rule so it can change what it
# subscribes to without editing the Approvals domain. The rule is tagged with
# its owner, and the target assumes the consumer's EventBridge forwarding role.
#
# Reads: /uni-prop/{UnicornApprovalsNamespace, UnicornWebNamespace}
#        /uni-prop/<stage>/{ApprovalsEventBusArn, WebEventBusArn, WebEventBridgeRoleArn}

#################################################################################################
#### DATA SOURCES (SSM operational contracts)
#################################################################################################

data "aws_ssm_parameter" "unicorn_web_namespace" {
  name = "/uni-prop/UnicornWebNamespace"
}

data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name = "/uni-prop/UnicornApprovalsNamespace"
}

data "aws_ssm_parameter" "approvals_event_bus_arn" {
  name = "/uni-prop/${var.stage}/ApprovalsEventBusArn"
}

data "aws_ssm_parameter" "web_event_bus_arn" {
  name = "/uni-prop/${var.stage}/WebEventBusArn"
}

data "aws_ssm_parameter" "web_eventbridge_role_arn" {
  name = "/uni-prop/${var.stage}/WebEventBridgeRoleArn"
}

#################################################################################################
#### SUBSCRIPTION RULE AND TARGET
#################################################################################################

resource "aws_cloudwatch_event_rule" "publication_evaluation_completed_subscription" {
  name           = "${local.unicorn_web_namespace}-PublicationEvaluationCompleted"
  description    = "Subscription rule for PublicationEvaluationCompleted events from the Unicorn Approvals service, forwarded to the Unicorn Web event bus."
  event_bus_name = local.approvals_event_bus_arn

  event_pattern = jsonencode({
    source      = [local.unicorn_approvals_namespace]
    detail-type = ["PublicationEvaluationCompleted"]
  })

  tags = {
    "rule-owner-service-namespace" = local.unicorn_web_namespace
  }
}

# The SAM subscription template defines no DLQ for this cross-bus target, and
# retry and dead-letter behavior is a must-match parity surface (PARITY.md).
# tflint-ignore: aws_cloudwatch_event_target_no_dlq
resource "aws_cloudwatch_event_target" "publication_evaluation_completed_subscription" {
  rule           = aws_cloudwatch_event_rule.publication_evaluation_completed_subscription.name
  event_bus_name = local.approvals_event_bus_arn
  target_id      = "SendEventTo"
  arn            = local.web_event_bus_arn
  role_arn       = local.web_eventbridge_role_arn
}
