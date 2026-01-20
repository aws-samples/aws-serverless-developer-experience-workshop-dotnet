resource "aws_sqs_queue" "unicorn_web_ingest_dlq" {
  name                     = "UnicornWebIngestDLQ-${var.stage}"
  sqs_managed_sse_enabled  = true
  message_retention_period = 1209600
  tags                     = local.common_tags
}

resource "aws_sqs_queue" "unicorn_web_ingest_queue" {
  name                     = "UnicornWebIngestQueue-${var.stage}"
  sqs_managed_sse_enabled  = true
  message_retention_period = 1209600
  visibility_timeout_seconds = 20
  tags                     = local.common_tags

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.unicorn_web_ingest_dlq.arn
    maxReceiveCount     = 1
  })
}

resource "aws_sqs_queue" "publication_evaluation_event_handler_dlq" {
  name                     = "PublicationEvaluationEventHandlerDLQ-${var.stage}"
  sqs_managed_sse_enabled  = true
  message_retention_period = 1209600
  tags                     = local.common_tags
}








