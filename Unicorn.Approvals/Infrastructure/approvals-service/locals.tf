locals {
  logs_retention_days = var.stage == "prod" ? 14 : 3
  is_prod             = var.stage == "prod"
  log_level           = var.stage == "prod" ? "ERROR" : "INFO"
  project_name        = "AWS Serverless Developer Experience"
  common_tags = {
    stage     = var.stage
    project   = local.project_name
    namespace = data.aws_ssm_parameter.unicorn_approvals_namespace.value
  }
}
