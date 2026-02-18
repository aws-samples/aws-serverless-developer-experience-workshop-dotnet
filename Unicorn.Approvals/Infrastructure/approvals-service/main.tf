data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

data "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name = "/uni-prop/UnicornApprovalsNamespace"
}

data "aws_ssm_parameter" "unicorn_contracts_namespace" {
  name = "/uni-prop/UnicornContractsNamespace"
}

data "aws_ssm_parameter" "unicorn_web_namespace" {
  name = "/uni-prop/UnicornWebNamespace"
}

data "aws_ssm_parameter" "approvals_event_bus_name" {
  name = "/uni-prop/${var.stage}/ApprovalsEventBus"
}

data "aws_ssm_parameter" "approvals_event_bus_arn" {
  name = "/uni-prop/${var.stage}/ApprovalsEventBusArn"
}

data "aws_ssm_parameter" "images_bucket" {
  name = "/uni-prop/${var.stage}/ImagesBucket"
}

#################################################################################################
#### DYNAMODB TABLE
#################################################################################################

resource "aws_dynamodb_table" "contract_status_table" {
  name         = "ContractStatusTable-${var.stage}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PropertyId"

  attribute {
    name = "PropertyId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = local.common_tags
}

#################################################################################################
#### SQS QUEUES
#################################################################################################

resource "aws_sqs_queue" "approvals_event_bus_rule_dlq" {
  name                      = "ApprovalsEventBusRuleDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 604800
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "approvals_service_dlq" {
  name                      = "ApprovalsServiceDLQ-${var.stage}"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 604800
  tags                      = local.common_tags
}

#################################################################################################
#### LAMBDA FUNCTIONS
#################################################################################################

data "archive_file" "approvals_service" {
  type        = "zip"
  source_dir  = var.lambda_code_path
  output_path = "${path.module}/.terraform/approvals-service.zip"
  excludes    = ["bin", "obj", ".aws-sam"]
}

# ContractStatusChangedHandlerFunction
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

  tags = local.common_tags
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

resource "aws_iam_role_policy_attachment" "contract_status_changed_handler_xray" {
  role       = aws_iam_role.contract_status_changed_handler_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "contract_status_changed_handler" {
  filename         = data.archive_file.approvals_service.output_path
  function_name    = "uni-prop-${var.stage}-contract-status-changed-handler"
  role             = aws_iam_role.contract_status_changed_handler_role.arn
  handler          = "Unicorn.Approvals.ApprovalsService::Unicorn.Approvals.ApprovalsService.ContractStatusChangedEventHandler::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = data.archive_file.approvals_service.output_base64sha256

  environment {
    variables = {
      CONTRACT_STATUS_TABLE         = aws_dynamodb_table.contract_status_table.name
      EVENT_BUS                     = data.aws_ssm_parameter.approvals_event_bus_name.value
      SERVICE_NAMESPACE             = data.aws_ssm_parameter.unicorn_approvals_namespace.value
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = data.aws_ssm_parameter.unicorn_approvals_namespace.value
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = data.aws_ssm_parameter.unicorn_approvals_namespace.value
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "contract_status_changed_handler" {
  name              = "/aws/lambda/${aws_lambda_function.contract_status_changed_handler.function_name}"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

# EventBridge rule to trigger ContractStatusChangedHandler
resource "aws_cloudwatch_event_rule" "contract_status_changed" {
  name           = "unicorn-approvals-ContractStatusChanged"
  event_bus_name = data.aws_ssm_parameter.approvals_event_bus_name.value

  event_pattern = jsonencode({
    source      = [data.aws_ssm_parameter.unicorn_contracts_namespace.value]
    detail-type = ["ContractStatusChanged"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "contract_status_changed" {
  rule           = aws_cloudwatch_event_rule.contract_status_changed.name
  event_bus_name = data.aws_ssm_parameter.approvals_event_bus_name.value
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

# PropertiesApprovalSyncFunction
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

  tags = local.common_tags
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

resource "aws_iam_role_policy_attachment" "properties_approval_sync_xray" {
  role       = aws_iam_role.properties_approval_sync_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "properties_approval_sync" {
  filename         = data.archive_file.approvals_service.output_path
  function_name    = "uni-prop-${var.stage}-properties-approval-sync"
  role             = aws_iam_role.properties_approval_sync_role.arn
  handler          = "Unicorn.Approvals.ApprovalsService::Unicorn.Approvals.ApprovalsService.PropertiesApprovalSyncFunction::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = data.archive_file.approvals_service.output_base64sha256

  environment {
    variables = {
      CONTRACT_STATUS_TABLE         = aws_dynamodb_table.contract_status_table.name
      EVENT_BUS                     = data.aws_ssm_parameter.approvals_event_bus_name.value
      SERVICE_NAMESPACE             = data.aws_ssm_parameter.unicorn_approvals_namespace.value
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = data.aws_ssm_parameter.unicorn_approvals_namespace.value
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = data.aws_ssm_parameter.unicorn_approvals_namespace.value
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "properties_approval_sync" {
  name              = "/aws/lambda/${aws_lambda_function.properties_approval_sync.function_name}"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_lambda_event_source_mapping" "properties_approval_sync_dynamodb" {
  event_source_arn  = aws_dynamodb_table.contract_status_table.stream_arn
  function_name     = aws_lambda_function.properties_approval_sync.arn
  starting_position = "TRIM_HORIZON"
  batch_size        = 100
  maximum_retry_attempts = 3

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.approvals_service_dlq.arn
    }
  }
}

# WaitForContractApprovalFunction
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

  tags = local.common_tags
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

resource "aws_iam_role_policy_attachment" "wait_for_contract_approval_xray" {
  role       = aws_iam_role.wait_for_contract_approval_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_lambda_function" "wait_for_contract_approval" {
  filename         = data.archive_file.approvals_service.output_path
  function_name    = "uni-prop-${var.stage}-wait-for-contract-approval"
  role             = aws_iam_role.wait_for_contract_approval_role.arn
  handler          = "Unicorn.Approvals.ApprovalsService::Unicorn.Approvals.ApprovalsService.WaitForContractApprovalFunction::FunctionHandler"
  runtime          = "dotnet10"
  timeout          = 10
  memory_size      = 512
  architectures    = ["x86_64"]
  source_code_hash = data.archive_file.approvals_service.output_base64sha256

  environment {
    variables = {
      CONTRACT_STATUS_TABLE         = aws_dynamodb_table.contract_status_table.name
      EVENT_BUS                     = data.aws_ssm_parameter.approvals_event_bus_name.value
      SERVICE_NAMESPACE             = data.aws_ssm_parameter.unicorn_approvals_namespace.value
      POWERTOOLS_LOGGER_CASE        = "PascalCase"
      POWERTOOLS_SERVICE_NAME       = data.aws_ssm_parameter.unicorn_approvals_namespace.value
      POWERTOOLS_TRACE_DISABLED     = "false"
      POWERTOOLS_LOGGER_LOG_EVENT   = local.is_prod ? "false" : "true"
      POWERTOOLS_LOGGER_SAMPLE_RATE = local.is_prod ? "0.1" : "0"
      POWERTOOLS_METRICS_NAMESPACE  = data.aws_ssm_parameter.unicorn_approvals_namespace.value
      POWERTOOLS_LOG_LEVEL          = "INFO"
      LOG_LEVEL                     = "INFO"
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "wait_for_contract_approval" {
  name              = "/aws/lambda/${aws_lambda_function.wait_for_contract_approval.function_name}"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
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

  tags = local.common_tags
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
        Resource = "arn:${data.aws_partition.current.partition}:s3:::${data.aws_ssm_parameter.images_bucket.value}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = data.aws_ssm_parameter.approvals_event_bus_arn.value
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
  name              = "/aws/states/uni-prop-${var.stage}-ApprovalStateMachine"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_sfn_state_machine" "approval_state_machine" {
  name     = "uni-prop-${var.stage}-ApprovalStateMachine"
  role_arn = aws_iam_role.approval_state_machine_role.arn

  definition = templatefile("${path.module}/PropertyApproval.asl.yaml", {
    WaitForContractApprovalArn = aws_lambda_function.wait_for_contract_approval.arn
    TableName                  = aws_dynamodb_table.contract_status_table.name
    ImageUploadBucketName      = data.aws_ssm_parameter.images_bucket.value
    EventBusName               = data.aws_ssm_parameter.approvals_event_bus_name.value
    ServiceName                = data.aws_ssm_parameter.unicorn_approvals_namespace.value
  })

  tracing_configuration {
    enabled = true
  }

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.approval_state_machine.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = local.common_tags
}

# EventBridge rule to trigger the Step Functions state machine
resource "aws_cloudwatch_event_rule" "publication_approval_requested" {
  name           = "unicorn-approvals-PublicationApprovalRequested"
  event_bus_name = data.aws_ssm_parameter.approvals_event_bus_name.value

  event_pattern = jsonencode({
    source      = [data.aws_ssm_parameter.unicorn_web_namespace.value]
    detail-type = ["PublicationApprovalRequested"]
  })

  tags = local.common_tags
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

  tags = local.common_tags
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
  event_bus_name = data.aws_ssm_parameter.approvals_event_bus_name.value
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

#################################################################################################
#### EVENTBRIDGE CATCHALL
#################################################################################################

resource "aws_cloudwatch_log_group" "unicorn_approvals_catch_all" {
  name              = "/aws/events/${var.stage}/${data.aws_ssm_parameter.unicorn_approvals_namespace.value}-catchall"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_event_rule" "unicorn_approvals_catch_all" {
  name           = "approvals.catchall"
  description    = "Catchall rule used for development purposes."
  event_bus_name = data.aws_ssm_parameter.approvals_event_bus_name.value
  state          = "ENABLED"

  event_pattern = jsonencode({
    account = [data.aws_caller_identity.current.account_id]
    source = [
      data.aws_ssm_parameter.unicorn_contracts_namespace.value,
      data.aws_ssm_parameter.unicorn_web_namespace.value
    ]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "unicorn_approvals_catch_all" {
  rule           = aws_cloudwatch_event_rule.unicorn_approvals_catch_all.name
  event_bus_name = data.aws_ssm_parameter.approvals_event_bus_name.value
  target_id      = "UnicornApprovalsCatchAllLogGroupTarget-${var.stage}"
  arn            = aws_cloudwatch_log_group.unicorn_approvals_catch_all.arn
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_cloudwatch_log_group_policy" {
  policy_name = "EvBToCWLogs-${var.stage}-approvals-catchall"

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
