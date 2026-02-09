locals {
  logs_retention_days = var.stage == "prod" ? 14 : 3
  is_prod             = var.stage == "prod"
  log_level           = var.stage == "prod" ? "ERROR" : "INFO"
  project_name        = "AWS Serverless Developer Experience"
  common_tags = {
    stage     = var.stage
    project   = local.project_name
    namespace = data.aws_ssm_parameter.unicorn_web_namespace.value
  }
  api_openapi_spec = templatefile("${path.module}/api.yaml.tpl", {
    UnicornWebApiIntegrationRoleArn = aws_iam_role.unicorn_web_api_integration_role.arn
    UnicornWebIngestQueueName       = aws_sqs_queue.unicorn_web_ingest_queue.name
    SearchFunctionArn               = aws_lambda_function.search_function.arn
    AWS_Region                      = data.aws_region.current.id
    AWS_AccountId                   = data.aws_caller_identity.current.account_id
  })
}
