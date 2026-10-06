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

resource "aws_cloudwatch_event_target" "publication_evaluation_completed_subscription" {
  rule           = aws_cloudwatch_event_rule.publication_evaluation_completed_subscription.name
  event_bus_name = local.approvals_event_bus_arn
  target_id      = "SendEventTo"
  arn            = local.web_event_bus_arn
  role_arn       = local.web_eventbridge_role_arn
}
