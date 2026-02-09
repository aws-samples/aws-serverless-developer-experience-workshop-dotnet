locals {
  logs_retention_days = var.stage == "prod" ? 14 : 3
  is_prod             = var.stage == "prod"
  log_level           = var.stage == "prod" ? "ERROR" : "INFO"
  project_name        = "AWS Serverless Developer Experience"
  common_tags = {
    stage     = var.stage
    project   = local.project_name
    namespace = data.aws_ssm_parameter.unicorn_contracts_namespace.value
  }
  api_openapi_spec = templatefile("${path.module}/api.yaml.tpl", {
    UnicornContractsApiIntegrationRoleArn = aws_iam_role.unicorn_contracts_api_integration_role.arn
    UnicornContractsIngestQueueName       = aws_sqs_queue.unicorn_contracts_ingest_queue.name
    AWS_Region                            = data.aws_region.current.id
    AWS_AccountId                         = data.aws_caller_identity.current.account_id
  })
}
