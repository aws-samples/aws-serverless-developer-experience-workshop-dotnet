# Technology Stack & Build System

## Runtime and Language

- **.NET 10** (`net10.0`; SDK pinned in `global.json`) for all Lambda functions.
- **dotnet CLI** with `UnicornProperties.sln` and shared settings in `Directory.Build.props`.
- **Terraform** (`>= 1.11, < 2.0`) with AWS provider `~> 6.0` for infrastructure, deployment, and state ownership.
- **AWS SAM** only for native Terraform-hook builds and local Lambda invocation. SAM does not deploy infrastructure or own state on this branch.
- **GNU Make** as the canonical participant interface. Namespace Makefiles share backend and lifecycle helpers from `common.mk`.

## AWS Services

- **AWS Lambda** for serverless compute.
- **Amazon DynamoDB** for service persistence and streams. Terraform state locking uses S3-native `.tflock` objects.
- **Amazon EventBridge** for event buses, schema registries, and cross-service messaging.
- **AWS Step Functions** for the approval workflow.
- **Amazon API Gateway** for REST endpoints.
- **Amazon SQS** for ingest queues and dead-letter queues.
- **AWS Systems Manager Parameter Store** for cross-root operational contracts.
- **Amazon S3** for Terraform state and shared images.
- **AWS X-Ray** for distributed tracing.
- **Amazon CloudWatch** for logs, metrics, and API Gateway account-level logging.

## Key Libraries and Frameworks

- **AWS Lambda Powertools for .NET** (`AWS.Lambda.Powertools.Logging`, `Metrics`, and `Tracing`) for structured observability.
- **AWS SDK for .NET** packages with `Amazon.Lambda.*` event and serialization packages.
- **xUnit**, `Amazon.Lambda.TestUtilities`, **NSubstitute**, and coverlet for tests and coverage.
- NuGet `packages.lock.json` files committed per project.

## Infrastructure Ownership

The repository contains exactly 15 independent Terraform roots under `Unicorn.*/Infrastructure/`. Each root has its own backend key and committed `.terraform.lock.hcl`. The validator enforces Terraform and provider versions, the exact inventory, standard root files, singleton ownership, SSM contracts, SAM metadata, production protections, catch-all behavior, and logging behavior.

Cross-root values flow through SSM parameters, not Terraform remote state. Contracts and Web render API Gateway OpenAPI bodies from `api.yaml.tpl`; Approvals renders its Step Functions definition from `PropertyApproval.asl.json`.

The Shared `api-gateway-account` root is the sole account/Region owner of `aws_api_gateway_account`. API Gateway method logging in service roots depends operationally on that singleton.

## Make Targets

### Full-system orchestration

Run from the repository root. `STAGE` is required and must be `local`, `dev`, or `prod`:

```bash
make deploy-all STAGE=dev
make delete-all STAGE=dev
```

`deploy-all` bootstraps the state backend and applies Shared resources, domains, schemas and workloads, then subscriptions in five phases. `delete-all` runs stage-scoped operations in reverse and preserves the API Gateway account singleton and state backend.

### Namespace interface

Run from `Unicorn.Contracts/`, `Unicorn.Approvals/`, `Unicorn.Web/`, or `Unicorn.Shared/`. Service Makefiles default to `STAGE=local` and `REGION=ap-southeast-2`:

```bash
make init STAGE=local
make plan STAGE=local
make deploy STAGE=dev
make build STAGE=local
make local-invoke STAGE=local
make test
make lint
make clean
make delete STAGE=local
```

Service Makefiles retain domain, schema, workload, and subscription-specific variants. Shared retains singleton, namespace, and stage-specific image variants. Its aggregate `init` leaves the shared image root configured against the safe `local` backend key; use the matching stage-specific target for later image work.

Production plans are saved as `.terraform/prod.tfplan`. Review the saved plan immediately before applying it with `CONFIRM_PROD=APPLY`. Production destroy requires `CONFIRM_PROD=DESTROY`.

## Build and Packaging

`make build` restores the relevant .NET projects and calls `scripts/sam_build_terraform.py` with `TF_VAR_sam_build=true`. The service Terraform roots expose `sam_metadata_*` resources for this hook.

`make package-service` calls `scripts/package_dotnet_lambda.py` to create sorted, fixed-timestamp, normalized-permission ZIP files with atomic replacement. Plans package the current source, and Terraform freshness checks reject missing or stale packages with the `make package-service` remedy. Production apply consumes the reviewed package associated with the saved plan.

## SAM Commands

Supported SAM use is build and local invocation of Terraform-defined functions:

```bash
sam build --hook-name terraform
sam local invoke --hook-name terraform <terraform-resource-address> --skip-prepare-infra
```

Prefer `make build` and `make local-invoke` because they set the Terraform stage, Region, source paths, and default function address. The `samconfig.toml` files contain build settings only. Web intentionally sets `parallel = false` to avoid concurrent publishes racing on the shared `Common` output.

Use no SAM infrastructure deployment or synchronization workflow on this branch. Terraform owns plans, applies, deletes, and state.

## Validation

Run the complete infrastructure validation from the repository root:

```bash
python3 scripts/validate_infrastructure.py --checkov
```

The script runs repository invariants, `terraform fmt -check -recursive`, backend-disabled initialization and `terraform validate` for all 15 roots, then repository-wide Checkov. `.checkov.yml` documents 21 intentional workshop exceptions. CI runs the same command after the .NET test suite.

For a narrower service check, `make lint` runs `terraform validate` in that namespace's roots. Run `make test` for the owning xUnit projects or `dotnet test UnicornProperties.sln --configuration Release` for the full solution.

## Environment Variables

Terraform `aws_lambda_function` resources own Lambda environment configuration. Common variables include:

- `DYNAMODB_TABLE` or service-specific table variables.
- `EVENT_BUS` and `SERVICE_NAMESPACE`, resolved from Terraform resources and SSM contracts.
- `POWERTOOLS_SERVICE_NAME` and `POWERTOOLS_METRICS_NAMESPACE`.
- `POWERTOOLS_LOG_LEVEL`, `POWERTOOLS_LOGGER_CASE`, `POWERTOOLS_LOGGER_LOG_EVENT`, `POWERTOOLS_LOGGER_SAMPLE_RATE`, and `POWERTOOLS_TRACE_DISABLED`.
- `LOG_LEVEL` and workflow-specific identifiers.

Do not move these values into deleted SAM templates. Update the owning Terraform workload root and preserve parity with the authoritative SAM behavior.
