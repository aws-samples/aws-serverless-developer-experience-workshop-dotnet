locals {
  event_bus_name      = "unicorn-web-eventbus-${var.stage}"
  registry_name       = "${data.aws_ssm_parameter.unicorn_web_namespace.value}-${var.stage}"
  logs_retention_days = var.stage == "prod" ? 14 : 3
  is_prod             = var.stage == "prod"
  log_level           = var.stage == "prod" ? "ERROR" : "INFO"
  common_tags = {
    stage     = var.stage
    project   = "AWS Serverless Developer Experience"
    namespace = data.aws_ssm_parameter.unicorn_web_namespace.value
  }
}
