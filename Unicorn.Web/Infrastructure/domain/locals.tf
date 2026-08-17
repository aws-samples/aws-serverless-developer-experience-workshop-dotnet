locals {
  event_bus_name      = "unicorn-web-eventbus-${var.stage}"
  registry_name       = "${data.aws_ssm_parameter.unicorn_web_namespace.value}-${var.stage}"
  logs_retention_days = var.stage == "prod" ? 14 : 3
  log_level           = var.stage == "prod" ? "ERROR" : "INFO"
}
