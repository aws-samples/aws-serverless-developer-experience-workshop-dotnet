# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  # SSM parameter values are marked sensitive by the AWS provider; the namespace
  # values are public workshop constants, so unwrap them for use in names/outputs.
  unicorn_contracts_namespace = nonsensitive(data.aws_ssm_parameter.unicorn_contracts_namespace.value)
  event_bus_name              = "unicorn-contracts-eventbus-${var.stage}"
  registry_name               = "${local.unicorn_contracts_namespace}-${var.stage}"
  logs_retention_days         = var.stage == "prod" ? 14 : 3
  log_level                   = var.stage == "prod" ? "ERROR" : "INFO"
}
