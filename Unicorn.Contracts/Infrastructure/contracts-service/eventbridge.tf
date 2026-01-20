data "aws_ssm_parameter" "contracts_event_bus_name" {
  name = "/uni-prop/${var.stage}/ContractsEventBus"
}

resource "aws_cloudwatch_log_group" "unicorn_contracts_catch_all" {
  name              = "/aws/events/${var.stage}/${data.aws_ssm_parameter.unicorn_contracts_namespace.value}-catchall"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_event_rule" "unicorn_contracts_catch_all" {
  name           = "${data.aws_ssm_parameter.unicorn_contracts_namespace.value}-CatchAllEvents"
  description    = "Catch all events published by the Contracts service."
  event_bus_name = data.aws_ssm_parameter.contracts_event_bus_name.value
  state          = "ENABLED"

  event_pattern = jsonencode({
    account = [data.aws_caller_identity.current.account_id]
    source  = [data.aws_ssm_parameter.unicorn_contracts_namespace.value]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_cloudwatch_log_group_policy" {
  policy_name = "EvBToCWLogs-${var.stage}-contracts-catchall"

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
        Resource = aws_cloudwatch_log_group.unicorn_contracts_catch_all.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "unicorn_contracts_catch_all" {
  rule           = aws_cloudwatch_event_rule.unicorn_contracts_catch_all.name
  event_bus_name = data.aws_ssm_parameter.contracts_event_bus_name.value
  target_id      = "UnicornContractsCatchAllLogGroupTarget-${var.stage}"
  arn            = aws_cloudwatch_log_group.unicorn_contracts_catch_all.arn
}

resource "aws_cloudwatch_log_group" "contracts_table_stream_to_event_pipe" {
  name              = "/aws/pipes/uni-prop-${var.stage}-contracts-table-stream-to-event-pipe"
  retention_in_days = local.logs_retention_days
  tags              = local.common_tags
}

resource "aws_iam_role" "contracts_table_stream_to_event_pipe_role" {
  name = "uni-prop-${var.stage}-contracts-table-stream-to-event-pipe-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "pipes.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "contracts_table_stream_to_event_pipe_policy" {
  name = "ContractsTableStreamToEventPipePolicy"
  role = aws_iam_role.contracts_table_stream_to_event_pipe_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:ListStreams"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ]
        Resource = aws_dynamodb_table.contracts_table.stream_arn
      },
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = data.aws_ssm_parameter.contracts_event_bus_arn.value
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.contracts_table_stream_to_event_pipe_dlq.arn
      }
    ]
  })
}

resource "aws_pipes_pipe" "contracts_table_stream_to_event_pipe" {
  name     = "uni-prop-${var.stage}-contracts-table-stream-to-event-pipe"
  role_arn = aws_iam_role.contracts_table_stream_to_event_pipe_role.arn
  source   = aws_dynamodb_table.contracts_table.stream_arn
  target   = data.aws_ssm_parameter.contracts_event_bus_arn.value

  source_parameters {
    dynamodb_stream_parameters {
      maximum_retry_attempts = 3
      batch_size             = 1
      starting_position       = "LATEST"
    }

    filter_criteria {
      filter {
        pattern = jsonencode({
          eventName = ["INSERT", "MODIFY"]
          dynamodb = {
            NewImage = {
              contract_status = {
                S = ["DRAFT", "APPROVED"]
              }
            }
          }
        })
      }
    }

    dead_letter_config {
      arn = aws_sqs_queue.contracts_table_stream_to_event_pipe_dlq.arn
    }
  }

  target_parameters {
    eventbridge_event_bus_parameters {
      detail_type = "ContractStatusChanged"
      source      = data.aws_ssm_parameter.unicorn_contracts_namespace.value
    }

    input_template = jsonencode({
      PropertyId            = "<$.dynamodb.Keys.PropertyId.S>"
      ContractId            = "<$.dynamodb.NewImage.ContractId.S>"
      ContractStatus        = "<$.dynamodb.NewImage.ContractStatus.S>"
      ContractLastModifiedOn = "<$.dynamodb.NewImage.ContractLastModifiedOn.S>"
    })
  }

  log_configuration {
    cloudwatch_logs_log_destination {
      log_group_arn = aws_cloudwatch_log_group.contracts_table_stream_to_event_pipe.arn
    }
    level = "ERROR"
  }

  tags = local.common_tags
}








