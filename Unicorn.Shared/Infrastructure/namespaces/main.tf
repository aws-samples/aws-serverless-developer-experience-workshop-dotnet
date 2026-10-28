# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Global service namespaces (deployment phase 2: shared).
#
# These account-global parameters are the event source values for each service
# and are read by every stage of every other root. Renaming or removing one is a
# cross-root and cross-IaC breaking change. Deleting this root requires
# CONFIRM_ACCOUNT_GLOBAL=DESTROY because it affects all stages.

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
