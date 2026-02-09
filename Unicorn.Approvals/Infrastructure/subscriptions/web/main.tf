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

resource "aws_cloudwatch_event_rule" "publication_approval_requested_subscription" {
  name           = "${data.aws_ssm_parameter.unicorn_approvals_namespace.value}-PublicationApprovalRequested"
  description    = "Subscription rule for PublicationApprovalRequested events from the Unicorn Web service, triggering the Approval workflow."
  event_bus_name = data.aws_ssm_parameter.web_event_bus_arn.value

  event_pattern = jsonencode({
    source      = [data.aws_ssm_parameter.unicorn_web_namespace.value]
    detail-type = ["PublicationApprovalRequested"]
  })

  tags = {
    "rule-owner-service-namespace" = data.aws_ssm_parameter.unicorn_approvals_namespace.value
  }
}

resource "aws_cloudwatch_event_target" "publication_approval_requested_subscription" {
  rule           = aws_cloudwatch_event_rule.publication_approval_requested_subscription.name
  event_bus_name = data.aws_ssm_parameter.web_event_bus_arn.value
  target_id      = "SendEventTo"
  arn            = data.aws_ssm_parameter.approvals_event_bus_arn.value
  role_arn       = data.aws_ssm_parameter.approvals_eventbridge_role_arn.value
}
