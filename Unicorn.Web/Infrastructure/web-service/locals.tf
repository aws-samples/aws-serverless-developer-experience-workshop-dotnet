locals {
  # Mirrors SAM's ${AWS::StackName} (stack_name in the develop samconfig.toml).
  # SAM derives the Logs resource policy name from it.
  stack_name                                = "uni-prop-${var.stage}-web"
  logs_retention_days                       = var.stage == "prod" ? 14 : 3
  is_prod                                   = var.stage == "prod"
  log_level                                 = var.stage == "prod" ? "ERROR" : "INFO"
  aws_account_id                            = var.sam_build ? "000000000000" : data.aws_caller_identity.current[0].account_id
  unicorn_web_namespace                     = var.sam_build ? "unicorn-web" : data.aws_ssm_parameter.unicorn_web_namespace[0].value
  unicorn_approvals_namespace               = var.sam_build ? "unicorn-approvals" : data.aws_ssm_parameter.unicorn_approvals_namespace[0].value
  search_project_path                       = abspath("${var.search_service_code_path}/SearchService.csproj")
  search_build_path                         = abspath("${path.module}/.terraform/build/search-service")
  search_package_path                       = "${path.module}/.terraform/search-service.zip"
  search_package_manifest_path              = "${local.search_package_path}.manifest.json"
  publication_manager_project_path          = abspath("${var.publication_manager_code_path}/PublicationManagerService.csproj")
  publication_manager_build_path            = abspath("${path.module}/.terraform/build/publication-manager-service")
  publication_manager_package_path          = "${path.module}/.terraform/publication-manager-service.zip"
  publication_manager_package_manifest_path = "${local.publication_manager_package_path}.manifest.json"
  common_code_path                          = abspath("${path.module}/../../Common")
  repository_root_path                      = abspath("${var.search_service_code_path}/../..")
  directory_build_props_path                = "${local.repository_root_path}/Directory.Build.props"
  global_json_path                          = "${local.repository_root_path}/global.json"
  package_script_path                       = "${local.repository_root_path}/scripts/package_dotnet_lambda.py"
  package_freshness_script_path             = "${local.repository_root_path}/scripts/check_lambda_package.py"
  search_source_files = sort([
    for file in fileset(var.search_service_code_path, "**") : file
    if !startswith(file, "bin/") && !startswith(file, "obj/") && !startswith(file, ".aws-sam/")
  ])
  publication_manager_source_files = sort([
    for file in fileset(var.publication_manager_code_path, "**") : file
    if !startswith(file, "bin/") && !startswith(file, "obj/") && !startswith(file, ".aws-sam/")
  ])
  common_source_files = sort([
    for file in fileset(local.common_code_path, "**") : file
    if !startswith(file, "bin/") && !startswith(file, "obj/") && !startswith(file, ".aws-sam/")
  ])
  shared_build_input_records = [
    "Directory.Build.props:${filesha256(local.directory_build_props_path)}",
    "global.json:${filesha256(local.global_json_path)}",
    "scripts/package_dotnet_lambda.py:${filesha256(local.package_script_path)}"
  ]
  search_source_records = sort(concat(
    [for file in local.search_source_files : "Unicorn.Web/SearchService/${file}:${filesha256("${var.search_service_code_path}/${file}")}"],
    [for file in local.common_source_files : "Unicorn.Web/Common/${file}:${filesha256("${local.common_code_path}/${file}")}"],
    local.shared_build_input_records
  ))
  search_source_hash  = sha256(jsonencode(local.search_source_records))
  search_package_hash = fileexists(local.search_package_path) ? filebase64sha256(local.search_package_path) : base64sha256(local.search_source_hash)
  publication_manager_source_records = sort(concat(
    [for file in local.publication_manager_source_files : "Unicorn.Web/PublicationManagerService/${file}:${filesha256("${var.publication_manager_code_path}/${file}")}"],
    [for file in local.common_source_files : "Unicorn.Web/Common/${file}:${filesha256("${local.common_code_path}/${file}")}"],
    local.shared_build_input_records
  ))
  publication_manager_source_hash  = sha256(jsonencode(local.publication_manager_source_records))
  publication_manager_package_hash = fileexists(local.publication_manager_package_path) ? filebase64sha256(local.publication_manager_package_path) : base64sha256(local.publication_manager_source_hash)
  web_event_bus_name               = var.sam_build ? "unicorn-web-eventbus-${var.stage}" : data.aws_ssm_parameter.web_event_bus_name[0].value
  # Hand-built ARNs keep sam_build deterministic without live AWS lookups.
  web_event_bus_arn = var.sam_build ? "arn:${data.aws_partition.current.partition}:events:${data.aws_region.current.region}:${local.aws_account_id}:event-bus/${local.web_event_bus_name}" : data.aws_ssm_parameter.web_event_bus_arn[0].value
  # These ARNs are assembled for deterministic api.yaml.tpl rendering during sam_build.
  web_api_integration_role_arn = "arn:${data.aws_partition.current.partition}:iam::${local.aws_account_id}:role/${aws_iam_role.unicorn_web_api_integration_role.name}"
  search_function_arn          = "arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.region}:${local.aws_account_id}:function:${aws_lambda_function.search_function.function_name}"
  api_openapi_spec = templatefile("${path.module}/api.yaml.tpl", {
    UnicornWebApiIntegrationRoleArn = local.web_api_integration_role_arn
    UnicornWebIngestQueueName       = aws_sqs_queue.unicorn_web_ingest_queue.name
    SearchFunctionArn               = local.search_function_arn
    AWS_Partition                   = data.aws_partition.current.partition
    AWS_Region                      = data.aws_region.current.region
    AWS_AccountId                   = local.aws_account_id
  })
}
