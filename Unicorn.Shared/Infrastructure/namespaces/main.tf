resource "aws_ssm_parameter" "unicorn_contracts_namespace" {
  name  = "/uni-prop/UnicornContractsNamespace"
  type  = "String"
  value = "unicorn-contracts"
}

resource "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name  = "/uni-prop/UnicornApprovalsNamespace"
  type  = "String"
  value = "unicorn-approvals"
}

resource "aws_ssm_parameter" "unicorn_web_namespace" {
  name  = "/uni-prop/UnicornWebNamespace"
  type  = "String"
  value = "unicorn-web"
}



