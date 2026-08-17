locals {
  logs_retention_days         = var.stage == "prod" ? 14 : 3
  is_prod                     = var.stage == "prod"
  aws_account_id              = var.sam_build ? "000000000000" : data.aws_caller_identity.current[0].account_id
  unicorn_approvals_namespace = var.sam_build ? "unicorn-approvals" : data.aws_ssm_parameter.unicorn_approvals_namespace[0].value
  unicorn_contracts_namespace = var.sam_build ? "unicorn-contracts" : data.aws_ssm_parameter.unicorn_contracts_namespace[0].value
  unicorn_web_namespace       = var.sam_build ? "unicorn-web" : data.aws_ssm_parameter.unicorn_web_namespace[0].value
  approvals_event_bus_name    = var.sam_build ? "unicorn-approvals-eventbus-${var.stage}" : data.aws_ssm_parameter.approvals_event_bus_name[0].value
  approvals_event_bus_arn     = var.sam_build ? "arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${local.aws_account_id}:event-bus/${local.approvals_event_bus_name}" : data.aws_ssm_parameter.approvals_event_bus_arn[0].value
  images_bucket               = var.sam_build ? "uni-prop-${var.stage}-sam-build-images" : data.aws_ssm_parameter.images_bucket[0].value
  lambda_project_path         = abspath("${var.lambda_code_path}/ApprovalsService.csproj")
  lambda_build_path           = abspath("${path.module}/.terraform/build/approvals-service")
  lambda_package_path         = "${path.module}/.terraform/approvals-service.zip"
  package_script_path         = abspath("${var.lambda_code_path}/../../scripts/package_dotnet_lambda.py")
  lambda_source_files = sort([
    for file in fileset(var.lambda_code_path, "**") : file
    if !startswith(file, "bin/") && !startswith(file, "obj/") && !startswith(file, ".aws-sam/")
  ])
  lambda_source_hash = sha256(join("", concat(
    [for file in local.lambda_source_files : filesha256("${var.lambda_code_path}/${file}")],
    [filesha256(local.package_script_path)]
  )))
  lambda_package_hash = fileexists(local.lambda_package_path) ? filebase64sha256(local.lambda_package_path) : base64sha256(local.lambda_source_hash)
}
