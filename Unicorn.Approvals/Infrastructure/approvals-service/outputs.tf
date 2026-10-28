# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "contract_status_table_name" {
  description = "DynamoDB table storing contract status information"
  value       = aws_dynamodb_table.contract_status_table.name
}

output "contract_status_changed_handler_function_name" {
  description = "ContractStatusChangedHandler function name"
  value       = aws_lambda_function.contract_status_changed_handler.function_name
}

output "contract_status_changed_handler_function_arn" {
  description = "ContractStatusChangedHandler function ARN"
  value       = aws_lambda_function.contract_status_changed_handler.arn
}

output "properties_approval_sync_function_name" {
  description = "PropertiesApprovalSync function name"
  value       = aws_lambda_function.properties_approval_sync.function_name
}

output "properties_approval_sync_function_arn" {
  description = "PropertiesApprovalSync function ARN"
  value       = aws_lambda_function.properties_approval_sync.arn
}

output "wait_for_contract_approval_function_name" {
  description = "WaitForContractApproval function name"
  value       = aws_lambda_function.wait_for_contract_approval.function_name
}

output "wait_for_contract_approval_function_arn" {
  description = "WaitForContractApproval function ARN"
  value       = aws_lambda_function.wait_for_contract_approval.arn
}

output "approval_state_machine_name" {
  description = "Approval state machine name"
  value       = aws_sfn_state_machine.approval_state_machine.name
}

output "approval_state_machine_arn" {
  description = "Approval state machine ARN"
  value       = aws_sfn_state_machine.approval_state_machine.arn
}

output "unicorn_approvals_catch_all_log_group_arn" {
  description = "ARN of the log group that receives every event matched by the Approvals catch-all rule"
  value       = aws_cloudwatch_log_group.unicorn_approvals_catch_all.arn
}

output "approval_state_machine_log_group_name" {
  description = "Approval state machine log group name"
  value       = aws_cloudwatch_log_group.approval_state_machine.name
}
