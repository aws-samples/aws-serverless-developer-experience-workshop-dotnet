# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Unicorn Approvals service workload root (deployment phase 4: workloads).
#
# PublicationApprovalRequested events (forwarded from Web) start the approval
# state machine, which checks content and image safety and waits until the
# property's contract is approved. ContractStatusChanged events (forwarded from
# Contracts) keep ContractStatusTable current. The workflow publishes
# PublicationEvaluationCompleted to the Approvals event bus.
#
# Reads:  /uni-prop/{UnicornApprovalsNamespace, UnicornContractsNamespace, UnicornWebNamespace},
#         /uni-prop/<stage>/{ApprovalsEventBus, ApprovalsEventBusArn, ImagesBucket}
# Layout: locals.tf holds naming, sam_build placeholders, and packaging inputs;
#         PropertyApproval.asl.json is the Step Functions definition.

#################################################################################################
#### DATA SOURCES (skipped when sam_build = true; locals.tf supplies placeholders)
#################################################################################################

data "aws_caller_identity" "current" {
  count = var.sam_build ? 0 : 1
}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/UnicornApprovalsNamespace"
}

data "aws_ssm_parameter" "unicorn_contracts_namespace" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/UnicornContractsNamespace"
}

data "aws_ssm_parameter" "unicorn_web_namespace" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/UnicornWebNamespace"
}

data "aws_ssm_parameter" "approvals_event_bus_name" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/${var.stage}/ApprovalsEventBus"
}

data "aws_ssm_parameter" "approvals_event_bus_arn" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/${var.stage}/ApprovalsEventBusArn"
}

data "aws_ssm_parameter" "images_bucket" {
  count = var.sam_build ? 0 : 1
  name  = "/uni-prop/${var.stage}/ImagesBucket"
}

#################################################################################################
#### DYNAMODB TABLE
#################################################################################################

resource "aws_dynamodb_table" "contract_status_table" {
  name                        = "ContractStatusTable-${var.stage}"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "PropertyId"
  deletion_protection_enabled = local.is_prod

  attribute {
    name = "PropertyId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = local.is_prod
  }
}

#################################################################################################
#### SQS QUEUES
#################################################################################################

resource "aws_sqs_queue" "approvals_event_bus_rule_dlq" {
  name                      = "ApprovalsEventBusRuleDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 604800
}

resource "aws_sqs_queue" "approvals_service_dlq" {
  name                      = "ApprovalsServiceDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 604800
}

#################################################################################################
#### LAMBDA FUNCTIONS
#################################################################################################

# Lambda packaging. `make package-service` writes a deterministic ZIP and manifest
# under .terraform/. On a normal plan or apply, the external data source checks
# that the package matches the current source and the precondition stops the run
# if it is missing or stale. During `make build` (sam_build = true) the
# null_resource builds the package instead, and the sam_metadata_* resources tell
# the SAM Terraform hook where each function's source and built ZIP live.
data "external" "lambda_package_freshness" {
  count   = var.sam_build ? 0 : 1
  program = ["python3", local.package_freshness_script_path]

  query = {
    repo_root     = local.repository_root_path
    package_path  = local.lambda_package_path
    manifest_path = local.lambda_package_manifest_path
  }
}

resource "null_resource" "build_approvals_service" {
  triggers = {
    source_hash = local.lambda_source_hash
  }

  lifecycle {
    precondition {
      condition     = var.sam_build ? true : data.external.lambda_package_freshness[0].result.fresh == "true"
      error_message = "Lambda deployment package is missing or stale. Run `make package-service` from Unicorn.Approvals and retry."
    }
  }

  provisioner "local-exec" {
    command = var.sam_build ? "python3 \"${local.package_script_path}\" --project \"${local.lambda_project_path}\" --build-dir \"${local.lambda_build_path}\" --output \"${local.lambda_package_path}\"" : "true"
  }
}

resource "null_resource" "sam_metadata_contract_status_changed_handler" {
  triggers = {
    resource_name        = "aws_lambda_function.contract_status_changed_handler"
    resource_type        = "ZIP_LAMBDA_FUNCTION"
    original_source_code = var.sam_build ? abspath(var.lambda_code_path) : var.lambda_code_path
    built_output_path    = var.sam_build ? abspath(local.lambda_package_path) : local.lambda_package_path
  }

  depends_on = [null_resource.build_approvals_service]
}

resource "null_resource" "sam_metadata_properties_approval_sync" {
  triggers = {
    resource_name        = "aws_lambda_function.properties_approval_sync"
    resource_type        = "ZIP_LAMBDA_FUNCTION"
    original_source_code = var.sam_build ? abspath(var.lambda_code_path) : var.lambda_code_path
    built_output_path    = var.sam_build ? abspath(local.lambda_package_path) : local.lambda_package_path
  }

  depends_on = [null_resource.build_approvals_service]
}

resource "null_resource" "sam_metadata_wait_for_contract_approval" {
  triggers = {
    resource_name        = "aws_lambda_function.wait_for_contract_approval"
    resource_type        = "ZIP_LAMBDA_FUNCTION"
    original_source_code = var.sam_build ? abspath(var.lambda_code_path) : var.lambda_code_path
    built_output_path    = var.sam_build ? abspath(local.lambda_package_path) : local.lambda_package_path
  }

  depends_on = [null_resource.build_approvals_service]
}

# ContractStatusChangedHandlerFunction: records each contract's latest status
# in ContractStatusTable from ContractStatusChanged events.
resource "aws_iam_role" "contract_status_changed_handler_role" {
  name = "uni-prop-${var.stage}-contract-status-changed-handler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "contract_status_changed_handler_policy" {
  name = "ContractStatusChangedHandlerPolicy"
  role = aws_iam_role.contract_status_changed_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.contract_status_table.arn,
          "${aws_dynamodb_table.contract_status_table.arn}/index/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.approvals_service_dlq.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "contract_status_changed_handler_runtime_policy" {
  name = "LambdaRuntimeAccess"
  role = aws_iam_role.contract_status_changed_handler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${local.aws_account_id}:log-group:/aws/lambda/uni-prop-${var.stage}-contract-status-changed-handler:*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "contract_status_changed_handler_xray" {
  role       = aws_iam_role.contract_status_changed_handler_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "contract_status_changed_handler" {
  depends_on = [
    null_resource.build_approvals_service,
    aws_iam_role_policy.contract_status_changed_handler_policy,
    aws_iam_role_policy.contract_status_changed_handler_runtime_policy,
    aws_iam_role_policy_attachment.contract_status_changed_handler_xray,
    aws_cloudwatch_log_group.contract_status_changed_handler
  ]

  filename         = local.lambda_package_path
  function_name    = "uni-prop-${var.stage}-contract-status-changed-handler"
  role             = aws_iam_role.contract_status_changed_handler_role.arn
  handler          = "Unicorn.Approvals.ApprovalsService::Unicorn.Approvals.ApprovalsService.ContractStatusChangedEventHandler::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = local.lambda_package_hash

  environment {
    variables = {
      CONTRACT_STATUS_TABLE         = aws_dynamodb_table.contract_status_table.name
      EVENT_BUS                     = local.approvals_event_bus_name
      SERVICE_NAMESPACE             = local.unicorn_approvals_namespace
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = local.unicorn_approvals_namespace
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = local.unicorn_approvals_namespace
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "contract_status_changed_handler" {
  name              = "/aws/lambda/uni-prop-${var.stage}-contract-status-changed-handler"
  retention_in_days = local.logs_retention_days
}

# EventBridge rule to trigger ContractStatusChangedHandler. The literal name
# mirrors the SAM RuleName.
resource "aws_cloudwatch_event_rule" "contract_status_changed" {
  name           = "unicorn-approvals-ContractStatusChanged"
  event_bus_name = local.approvals_event_bus_name

  event_pattern = jsonencode({
    source      = [local.unicorn_contracts_namespace]
    detail-type = ["ContractStatusChanged"]
  })
}

resource "aws_cloudwatch_event_target" "contract_status_changed" {
  rule           = aws_cloudwatch_event_rule.contract_status_changed.name
  event_bus_name = local.approvals_event_bus_name
  target_id      = "ContractStatusChangedHandler"
  arn            = aws_lambda_function.contract_status_changed_handler.arn

  retry_policy {
    maximum_retry_attempts       = 5
    maximum_event_age_in_seconds = 900
  }

  dead_letter_config {
    arn = aws_sqs_queue.approvals_event_bus_rule_dlq.arn
  }
}

resource "aws_lambda_permission" "contract_status_changed_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contract_status_changed_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.contract_status_changed.arn
}

resource "aws_lambda_function_event_invoke_config" "contract_status_changed_handler" {
  function_name = aws_lambda_function.contract_status_changed_handler.function_name

  destination_config {
    on_failure {
      destination = aws_sqs_queue.approvals_service_dlq.arn
    }
  }
}

resource "aws_sqs_queue_policy" "approvals_event_bus_rule_dlq" {
  queue_url = aws_sqs_queue.approvals_event_bus_rule_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowContractStatusChangedRule"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.approvals_event_bus_rule_dlq.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.contract_status_changed.arn
        }
        StringEquals = {
          "aws:SourceAccount" = local.aws_account_id
        }
      }
    }]
  })
}

# PropertiesApprovalSyncFunction: reads the table stream and resumes paused
# workflow executions (SendTaskSuccess) once a contract is approved.
resource "aws_iam_role" "properties_approval_sync_role" {
  name = "uni-prop-${var.stage}-properties-approval-sync-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "properties_approval_sync_policy" {
  name = "PropertiesApprovalSyncPolicy"
  role = aws_iam_role.properties_approval_sync_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ]
        Resource = [
          aws_dynamodb_table.contract_status_table.arn,
          "${aws_dynamodb_table.contract_status_table.arn}/index/*",
          aws_dynamodb_table.contract_status_table.stream_arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.approvals_service_dlq.arn
      },
      {
        Effect   = "Allow"
        Action   = ["states:SendTaskSuccess"]
        Resource = aws_sfn_state_machine.approval_state_machine.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "properties_approval_sync_runtime_policy" {
  name = "LambdaRuntimeAccess"
  role = aws_iam_role.properties_approval_sync_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${local.aws_account_id}:log-group:/aws/lambda/uni-prop-${var.stage}-properties-approval-sync:*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "properties_approval_sync_xray" {
  role       = aws_iam_role.properties_approval_sync_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "properties_approval_sync" {
  depends_on = [
    null_resource.build_approvals_service,
    aws_iam_role_policy.properties_approval_sync_policy,
    aws_iam_role_policy.properties_approval_sync_runtime_policy,
    aws_iam_role_policy_attachment.properties_approval_sync_xray,
    aws_cloudwatch_log_group.properties_approval_sync
  ]

  filename         = local.lambda_package_path
  function_name    = "uni-prop-${var.stage}-properties-approval-sync"
  role             = aws_iam_role.properties_approval_sync_role.arn
  handler          = "Unicorn.Approvals.ApprovalsService::Unicorn.Approvals.ApprovalsService.PropertiesApprovalSyncFunction::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = local.lambda_package_hash

  environment {
    variables = {
      CONTRACT_STATUS_TABLE         = aws_dynamodb_table.contract_status_table.name
      EVENT_BUS                     = local.approvals_event_bus_name
      SERVICE_NAMESPACE             = local.unicorn_approvals_namespace
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = local.unicorn_approvals_namespace
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = local.unicorn_approvals_namespace
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "properties_approval_sync" {
  name              = "/aws/lambda/uni-prop-${var.stage}-properties-approval-sync"
  retention_in_days = local.logs_retention_days
}

resource "aws_lambda_function_event_invoke_config" "properties_approval_sync" {
  function_name = aws_lambda_function.properties_approval_sync.function_name

  destination_config {
    on_failure {
      destination = aws_sqs_queue.approvals_service_dlq.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "properties_approval_sync_dynamodb" {
  event_source_arn       = aws_dynamodb_table.contract_status_table.stream_arn
  function_name          = aws_lambda_function.properties_approval_sync.arn
  starting_position      = "TRIM_HORIZON"
  batch_size             = 100
  maximum_retry_attempts = 3

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.approvals_service_dlq.arn
    }
  }
}

# WaitForContractApprovalFunction: called by the state machine with a task
# token, which it stores until the contract is approved.
resource "aws_iam_role" "wait_for_contract_approval_role" {
  name = "uni-prop-${var.stage}-wait-for-contract-approval-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "wait_for_contract_approval_policy" {
  name = "WaitForContractApprovalPolicy"
  role = aws_iam_role.wait_for_contract_approval_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.contract_status_table.arn,
          "${aws_dynamodb_table.contract_status_table.arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "wait_for_contract_approval_runtime_policy" {
  name = "LambdaRuntimeAccess"
  role = aws_iam_role.wait_for_contract_approval_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${local.aws_account_id}:log-group:/aws/lambda/uni-prop-${var.stage}-wait-for-contract-approval:*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "wait_for_contract_approval_xray" {
  role       = aws_iam_role.wait_for_contract_approval_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "wait_for_contract_approval" {
  depends_on = [
    null_resource.build_approvals_service,
    aws_iam_role_policy.wait_for_contract_approval_policy,
    aws_iam_role_policy.wait_for_contract_approval_runtime_policy,
    aws_iam_role_policy_attachment.wait_for_contract_approval_xray,
    aws_cloudwatch_log_group.wait_for_contract_approval
  ]

  filename         = local.lambda_package_path
  function_name    = "uni-prop-${var.stage}-wait-for-contract-approval"
  role             = aws_iam_role.wait_for_contract_approval_role.arn
  handler          = "Unicorn.Approvals.ApprovalsService::Unicorn.Approvals.ApprovalsService.WaitForContractApprovalFunction::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = local.lambda_package_hash

  environment {
    variables = {
      CONTRACT_STATUS_TABLE         = aws_dynamodb_table.contract_status_table.name
      EVENT_BUS                     = local.approvals_event_bus_name
      SERVICE_NAMESPACE             = local.unicorn_approvals_namespace
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = local.unicorn_approvals_namespace
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = local.unicorn_approvals_namespace
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "wait_for_contract_approval" {
  name              = "/aws/lambda/uni-prop-${var.stage}-wait-for-contract-approval"
  retention_in_days = local.logs_retention_days
}

#################################################################################################
#### STATE MACHINE
#################################################################################################

resource "aws_iam_role" "approval_state_machine_role" {
  name = "uni-prop-${var.stage}-approval-state-machine-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "approval_state_machine_policy" {
  name = "ApprovalStateMachinePolicy"
  role = aws_iam_role.approval_state_machine_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "comprehend:DetectSentiment"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectModerationLabels"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.wait_for_contract_approval.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.contract_status_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::${local.images_bucket}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = local.approvals_event_bus_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "approval_state_machine_xray" {
  role       = aws_iam_role.approval_state_machine_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_cloudwatch_log_group" "approval_state_machine" {
  name              = "/aws/states/${local.stack_name}-ApprovalStateMachine"
  retention_in_days = local.logs_retention_days
}

# The workflow definition is PropertyApproval.asl.json; templatefile() fills in
# the function, table, bucket, bus, and service names.
resource "aws_sfn_state_machine" "approval_state_machine" {
  name     = "${local.stack_name}-ApprovalStateMachine"
  role_arn = aws_iam_role.approval_state_machine_role.arn

  definition = templatefile("${path.module}/PropertyApproval.asl.json", {
    WaitForContractApprovalArn = aws_lambda_function.wait_for_contract_approval.arn
    TableName                  = aws_dynamodb_table.contract_status_table.name
    ImageUploadBucketName      = local.images_bucket
    EventBusName               = local.approvals_event_bus_name
    ServiceName                = local.unicorn_approvals_namespace
  })

  tracing_configuration {
    enabled = true
  }

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.approval_state_machine.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
}

# EventBridge rule to trigger the Step Functions state machine. The literal
# name mirrors the SAM RuleName.
resource "aws_cloudwatch_event_rule" "publication_approval_requested" {
  name           = "unicorn-approvals-PublicationApprovalRequested"
  event_bus_name = local.approvals_event_bus_name

  event_pattern = jsonencode({
    source      = [local.unicorn_web_namespace]
    detail-type = ["PublicationApprovalRequested"]
  })
}

resource "aws_iam_role" "publication_approval_requested_target_role" {
  name = "uni-prop-${var.stage}-pub-approval-req-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "publication_approval_requested_target_policy" {
  name = "StartStateMachineExecution"
  role = aws_iam_role.publication_approval_requested_target_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = aws_sfn_state_machine.approval_state_machine.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "publication_approval_requested" {
  rule           = aws_cloudwatch_event_rule.publication_approval_requested.name
  event_bus_name = local.approvals_event_bus_name
  target_id      = "ApprovalStateMachine"
  arn            = aws_sfn_state_machine.approval_state_machine.arn
  role_arn       = aws_iam_role.publication_approval_requested_target_role.arn

  retry_policy {
    maximum_retry_attempts       = 5
    maximum_event_age_in_seconds = 900
  }

  dead_letter_config {
    arn = aws_sqs_queue.approvals_service_dlq.arn
  }
}

resource "aws_sqs_queue_policy" "approvals_service_dlq" {
  queue_url = aws_sqs_queue.approvals_service_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowPublicationApprovalRequestedRule"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.approvals_service_dlq.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.publication_approval_requested.arn
        }
        StringEquals = {
          "aws:SourceAccount" = local.aws_account_id
        }
      }
    }]
  })
}

#################################################################################################
#### EVENTBRIDGE CATCHALL
#################################################################################################

resource "aws_cloudwatch_log_group" "unicorn_approvals_catch_all" {
  name              = "/aws/events/${var.stage}/${local.unicorn_approvals_namespace}-catchall"
  retention_in_days = local.logs_retention_days
}

resource "aws_cloudwatch_event_rule" "unicorn_approvals_catch_all" {
  name           = "${local.unicorn_approvals_namespace}-CatchAllEvents"
  description    = "Catchall rule used for development purposes."
  event_bus_name = local.approvals_event_bus_name
  state          = "ENABLED"

  event_pattern = jsonencode({
    account = [local.aws_account_id]
    source = [
      local.unicorn_contracts_namespace,
      local.unicorn_web_namespace
    ]
  })
}

# The catch-all rule exists for debugging and writes to a log group; SAM excludes
# the matching serverless rule (ES4000), so this target has no DLQ either.
# tflint-ignore: aws_cloudwatch_event_target_no_dlq
resource "aws_cloudwatch_event_target" "unicorn_approvals_catch_all" {
  rule           = aws_cloudwatch_event_rule.unicorn_approvals_catch_all.name
  event_bus_name = local.approvals_event_bus_name
  target_id      = "UnicornApprovalsCatchAllLogGroupTarget-${var.stage}"
  arn            = aws_cloudwatch_log_group.unicorn_approvals_catch_all.arn
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_cloudwatch_log_group_policy" {
  policy_name = "EvBToCWLogs-${local.stack_name}"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "delivery.logs.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.unicorn_approvals_catch_all.arn}:*"
      }
    ]
  })
}
