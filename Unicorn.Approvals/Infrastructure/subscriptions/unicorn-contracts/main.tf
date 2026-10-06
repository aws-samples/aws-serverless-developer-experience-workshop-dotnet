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

resource "aws_cloudwatch_event_target" "contract_status_changed_subscription" {
  rule           = aws_cloudwatch_event_rule.contract_status_changed_subscription.name
  event_bus_name = local.contracts_event_bus_arn
  target_id      = "SendEventTo"
  arn            = local.approvals_event_bus_arn
  role_arn       = local.approvals_eventbridge_role_arn
}
