#!/usr/bin/env python3
"""Validate the .NET Terraform roots and cross-root architecture invariants."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]

EXPECTED_ROOTS = (
    Path("Unicorn.Contracts/Infrastructure/domain"),
    Path("Unicorn.Contracts/Infrastructure/contracts-service"),
    Path("Unicorn.Contracts/Infrastructure/schema-registry/ContractStatusChanged"),
    Path("Unicorn.Approvals/Infrastructure/domain"),
    Path("Unicorn.Approvals/Infrastructure/approvals-service"),
    Path("Unicorn.Approvals/Infrastructure/schema-registry/PublicationEvaluationCompleted"),
    Path("Unicorn.Approvals/Infrastructure/subscriptions/unicorn-contracts"),
    Path("Unicorn.Approvals/Infrastructure/subscriptions/unicorn-web"),
    Path("Unicorn.Web/Infrastructure/domain"),
    Path("Unicorn.Web/Infrastructure/web-service"),
    Path("Unicorn.Web/Infrastructure/schema-registry/PublicationApprovalRequested"),
    Path("Unicorn.Web/Infrastructure/subscriptions/approvals"),
    Path("Unicorn.Shared/Infrastructure/api-gateway-account"),
    Path("Unicorn.Shared/Infrastructure/namespaces"),
    Path("Unicorn.Shared/Infrastructure/uniprop-images"),
)

SERVICE_ROOTS = {
    Path("Unicorn.Contracts/Infrastructure/contracts-service"): 1,
    Path("Unicorn.Approvals/Infrastructure/approvals-service"): 3,
    Path("Unicorn.Web/Infrastructure/web-service"): 3,
}

REQUIRED_ROOT_FILES = (
    ".terraform.lock.hcl",
    "backend.tf",
    "main.tf",
    "outputs.tf",
    "providers.tf",
    "variables.tf",
)


class ValidationFailure(Exception):
    """Raised when a repository invariant is not satisfied."""


def read(relative_path: Path | str) -> str:
    return (REPOSITORY_ROOT / relative_path).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationFailure(message)


def require_text(text: str, expected: str, context: str) -> None:
    require(expected in text, f"{context}: expected {expected!r}")


def discover_roots() -> set[Path]:
    roots: set[Path] = set()
    for provider_file in REPOSITORY_ROOT.glob("Unicorn.*/Infrastructure/**/providers.tf"):
        roots.add(provider_file.parent.relative_to(REPOSITORY_ROOT))
    return roots


def validate_inventory() -> None:
    expected = set(EXPECTED_ROOTS)
    discovered = discover_roots()
    require(
        discovered == expected,
        "Terraform root inventory differs from the approved 15 roots. "
        f"Missing: {sorted(map(str, expected - discovered))}; "
        f"unexpected: {sorted(map(str, discovered - expected))}",
    )

    for root in EXPECTED_ROOTS:
        missing = [name for name in REQUIRED_ROOT_FILES if not (REPOSITORY_ROOT / root / name).is_file()]
        require(not missing, f"{root}: missing standard root files: {', '.join(missing)}")

        providers = read(root / "providers.tf")
        require_text(providers, 'required_version = ">= 1.6, < 2.0"', str(root))
        require(
            re.search(r'aws\s*=\s*\{.*?version\s*=\s*"~> 6\.0"', providers, re.DOTALL) is not None,
            f"{root}: AWS provider must be constrained to ~> 6.0",
        )
        require_text(providers, "default_tags", f"{root}: AWS provider must declare default_tags")


def validate_terraform_style() -> None:
    all_terraform = "\n".join(path.read_text(encoding="utf-8") for root in EXPECTED_ROOTS for path in (REPOSITORY_ROOT / root).glob("*.tf"))
    forbidden = {
        "inline_policy {": "deprecated IAM inline_policy block",
        "managed_policy_arns": "deprecated managed_policy_arns argument",
        "message_retention_period": "invalid SQS retention argument",
        "data.aws_region.current.id": "deprecated AWS provider v6 region attribute",
    }
    for token, description in forbidden.items():
        require(token not in all_terraform, f"Terraform contains {description}: {token}")

    for deployment in re.finditer(
        r'resource\s+"aws_api_gateway_deployment".*?(?=\nresource\s+"|\Z)',
        all_terraform,
        re.DOTALL,
    ):
        require(
            re.search(r"^\s*stage_name\s*=", deployment.group(0), re.MULTILINE) is None,
            "aws_api_gateway_deployment must not set stage_name; use aws_api_gateway_stage",
        )


def validate_singleton_ownership() -> None:
    owners: list[Path] = []
    for root in EXPECTED_ROOTS:
        main = read(root / "main.tf")
        if 'resource "aws_api_gateway_account"' in main:
            owners.append(root)

    expected_owner = Path("Unicorn.Shared/Infrastructure/api-gateway-account")
    require(owners == [expected_owner], f"aws_api_gateway_account must be owned only by {expected_owner}; found {owners}")


def validate_lambda_packaging_and_parity() -> None:
    for root, expected_metadata_count in SERVICE_ROOTS.items():
        main = read(root / "main.tf")
        providers = read(root / "providers.tf")
        require(
            main.count('resource "null_resource" "sam_metadata_') == expected_metadata_count,
            f"{root}: expected {expected_metadata_count} sam_metadata resources",
        )
        require_text(main, "built_output_path", str(root))
        require_text(main, "original_source_code", str(root))
        require_text(main, "resource_type", str(root))
        require_text(main, "ZIP_LAMBDA_FUNCTION", str(root))
        require_text(main, "source_code_hash", str(root))
        require_text(providers, 'version = "~> 3.2"', f"{root} null provider")

    contracts = read("Unicorn.Contracts/Infrastructure/contracts-service/main.tf")
    approvals = read("Unicorn.Approvals/Infrastructure/approvals-service/main.tf")
    web = read("Unicorn.Web/Infrastructure/web-service/main.tf")

    for text, context in ((contracts, "Contracts"), (web, "Web")):
        for action in ("sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"):
            require_text(text, action, f"{context} SQS poller policy")

    for text, context in ((contracts, "Contracts"), (approvals, "Approvals"), (web, "Web")):
        require_text(text, "logs:CreateLogStream", f"{context} Lambda logging policy")
        require_text(text, "logs:PutLogEvents", f"{context} Lambda logging policy")

    require_text(approvals, 'resource "aws_lambda_function_event_invoke_config" "contract_status_changed_handler"', "Approvals async failure destination")
    require_text(approvals, 'resource "aws_sqs_queue_policy" "approvals_event_bus_rule_dlq"', "Approvals EventBridge DLQ policy")
    require_text(approvals, 'resource "aws_sqs_queue_policy" "approvals_service_dlq"', "Approvals service DLQ policy")
    require_text(web, 'resource "aws_lambda_function_event_invoke_config" "publication_evaluation_event_handler"', "Web async failure destination")


def validate_contracts_and_production_safety() -> None:
    contracts_schema = read("Unicorn.Contracts/Infrastructure/schema-registry/ContractStatusChanged/locals.tf")
    web_schema = read("Unicorn.Web/Infrastructure/schema-registry/PublicationApprovalRequested/locals.tf")
    contracts_service = read("Unicorn.Contracts/Infrastructure/contracts-service/main.tf")

    for property_name in ("PropertyId", "ContractId", "ContractStatus", "ContractLastModifiedOn"):
        require_text(contracts_schema, property_name, "ContractStatusChanged schema")
    require("contract_status" not in contracts_service, "Contracts Pipe must filter and transform PascalCase ContractStatus")
    require_text(contracts_service, "ContractStatus", "Contracts Pipe")

    for property_name in (
        "PropertyId",
        "Status",
        "Description",
        "Images",
        "Address",
        "Country",
        "City",
        "Street",
        "Number",
    ):
        require_text(web_schema, property_name, "PublicationApprovalRequested schema")

    service_mains = [read(root / "main.tf") for root in SERVICE_ROOTS]
    for root, main in zip(SERVICE_ROOTS, service_mains, strict=True):
        require_text(main, "deletion_protection_enabled = local.is_prod", f"{root} DynamoDB")
        require_text(main, "enabled = local.is_prod", f"{root} point-in-time recovery")
        require_text(main, 'local.is_prod ? "DISABLED" : "ENABLED"', f"{root} catch-all rule")

    approvals = read("Unicorn.Approvals/Infrastructure/approvals-service/main.tf")
    require_text(approvals, "include_execution_data = !local.is_prod", "Approvals Step Functions logging")
    require_text(approvals, 'level                  = local.is_prod ? "ERROR" : "ALL"', "Approvals Step Functions logging")
    for invoke_config in (
        '"aws_lambda_function_event_invoke_config" "contract_status_changed_handler"',
        '"aws_lambda_function_event_invoke_config" "properties_approval_sync"',
    ):
        require_text(approvals, invoke_config, "Approvals async OnFailure destination (justifies CKV_AWS_116 skip)")

    images = read("Unicorn.Shared/Infrastructure/uniprop-images/main.tf")
    require_text(images, 'resource "aws_s3_bucket_public_access_block"', "Shared images bucket")
    require_text(images, 'resource "aws_s3_bucket_server_side_encryption_configuration"', "Shared images bucket")
    require_text(images, 'local.is_prod ? "Enabled" : "Suspended"', "Shared images bucket versioning")


def validate_ssm_contracts() -> None:
    required_parameters = (
        "/uni-prop/UnicornContractsNamespace",
        "/uni-prop/UnicornApprovalsNamespace",
        "/uni-prop/UnicornWebNamespace",
        "/uni-prop/${var.stage}/ContractsEventBusArn",
        "/uni-prop/${var.stage}/ApprovalsEventBusArn",
        "/uni-prop/${var.stage}/WebEventBusArn",
    )
    all_main_files = "\n".join(read(root / "main.tf") for root in EXPECTED_ROOTS)
    for parameter in required_parameters:
        require_text(all_main_files, parameter, "Operational SSM contracts")


def validate_repository_invariants() -> None:
    validate_inventory()
    validate_terraform_style()
    validate_singleton_ownership()
    validate_lambda_packaging_and_parity()
    validate_contracts_and_production_safety()
    validate_ssm_contracts()


def run(command: list[str], cwd: Path = REPOSITORY_ROOT) -> None:
    printable = " ".join(command)
    print(f"+ ({cwd.relative_to(REPOSITORY_ROOT) or Path('.')}) {printable}")
    completed = subprocess.run(command, cwd=cwd, check=False)
    if completed.returncode != 0:
        raise ValidationFailure(f"Command failed with exit code {completed.returncode}: {printable}")


def resolve_terraform_command() -> str:
    require(shutil.which("terraform") is not None, "Terraform command not found: terraform")
    return "terraform"


def validate_with_tools(args: argparse.Namespace) -> None:
    terraform_command = resolve_terraform_command()
    run([terraform_command, "fmt", "-check", "-recursive"])

    for root in EXPECTED_ROOTS:
        root_path = REPOSITORY_ROOT / root
        if not args.skip_init:
            run(
                [terraform_command, "init", "-backend=false", "-input=false", "-lockfile=readonly"],
                root_path,
            )
        run([terraform_command, "validate", "-no-color"], root_path)
        if args.tflint:
            run(["tflint", "--chdir", str(root_path)])

    if args.checkov:
        run(["checkov", "--directory", str(REPOSITORY_ROOT), "--framework", "terraform", "--quiet"])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-init", action="store_true", help="Skip backend-disabled provider initialization")
    parser.add_argument("--static-only", action="store_true", help="Run repository invariant checks without external tools")
    parser.add_argument("--tflint", action="store_true", help="Run tflint in every Terraform root")
    parser.add_argument("--checkov", action="store_true", help="Run Checkov across the repository after root validation")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        validate_repository_invariants()
        print(f"Static infrastructure validation passed for {len(EXPECTED_ROOTS)} Terraform roots.")
        if not args.static_only:
            validate_with_tools(args)
    except ValidationFailure as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print("Infrastructure validation completed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
