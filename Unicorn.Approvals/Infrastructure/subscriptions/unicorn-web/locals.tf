locals {
  # SSM marks parameter values sensitive. These namespaces and ARNs are public
  # operational contracts, so unwrap each once before using it in resources.
  unicorn_approvals_namespace    = nonsensitive(data.aws_ssm_parameter.unicorn_approvals_namespace.value)
  unicorn_web_namespace          = nonsensitive(data.aws_ssm_parameter.unicorn_web_namespace.value)
  web_event_bus_arn              = nonsensitive(data.aws_ssm_parameter.web_event_bus_arn.value)
  approvals_event_bus_arn        = nonsensitive(data.aws_ssm_parameter.approvals_event_bus_arn.value)
  approvals_eventbridge_role_arn = nonsensitive(data.aws_ssm_parameter.approvals_eventbridge_role_arn.value)
}
