resource "aws_sqs_queue" "unicorn_contracts_ingest_dlq" {
  name                       = "UnicornContractsIngestDLQ-${var.stage}"
  sqs_managed_sse_enabled    = true
  message_retention_period   = 1209600
  tags                       = local.common_tags
}

resource "aws_sqs_queue" "unicorn_contracts_ingest_queue" {
  name                       = "UnicornContractsIngestQueue-${var.stage}"
  sqs_managed_sse_enabled    = true
  message_retention_period   = 1209600
  visibility_timeout_seconds = 20
  tags                       = local.common_tags

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.unicorn_contracts_ingest_dlq.arn
    maxReceiveCount     = 1
  })
}

resource "aws_sqs_queue" "contracts_table_stream_to_event_pipe_dlq" {
  name                     = "ContractsTableStreamToEventPipeDLQ-${var.stage}"
  sqs_managed_sse_enabled  = true
  message_retention_period = 1209600
  tags                     = local.common_tags
}








