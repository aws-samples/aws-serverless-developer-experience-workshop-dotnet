# Project Structure & Conventions

## Repository Layout

This repository is a multi-service .NET monorepo with Terraform-owned infrastructure:

```text
├── Unicorn.Contracts/      # Contracts service and owned Terraform roots
├── Unicorn.Approvals/      # Approval workflow and owned Terraform roots
├── Unicorn.Web/            # Property listing/search service and owned Terraform roots
├── Unicorn.Shared/         # Account/Region and cross-service Terraform roots
├── scripts/                # Packaging and infrastructure validation tools
├── docs/                   # Documentation and architecture diagrams
├── Makefile                # Five-phase full-system Terraform orchestration
├── common.mk               # Shared Terraform backend and lifecycle helpers
├── PARITY.md               # SAM-to-Terraform mirror contract
├── UnicornProperties.sln   # Solution referencing all projects
├── Directory.Build.props   # Shared MSBuild settings
└── global.json             # .NET SDK version pin
```

Terraform is the deployment and state owner. AWS SAM is retained only for build and local invocation of Terraform-defined Lambda functions through the native Terraform hook.

## Service Structure Pattern

Each service follows this structure. Maintain it when adding or modifying services:

```text
Unicorn.<Service>/
├── Makefile                     # Canonical build, Terraform lifecycle, and test interface
├── <Name>Service/               # Lambda project (PascalCase)
│   ├── <Name>Service.csproj     # Dependencies; packages.lock.json is committed
│   └── *.cs                     # Handlers and domain types
├── <Name>Service.Test(s)/       # xUnit test project
│   ├── *.cs                     # Tests and helpers
│   └── events/                  # Sample event payloads
└── Infrastructure/              # Independent Terraform roots owned by the service
```

`Unicorn.Web` contains multiple projects: `PublicationManagerService`, `SearchService`, `Common`, and `Data`. Approvals keeps the Step Functions definition at `Unicorn.Approvals/Infrastructure/approvals-service/PropertyApproval.asl.json`; Terraform renders this JSON ASL file into the state machine definition.

## Fifteen Terraform Roots

Every directory below is an independent Terraform root with its own backend key and committed `.terraform.lock.hcl`:

| Owner | Terraform root | Responsibility |
| --- | --- | --- |
| Contracts | `Unicorn.Contracts/Infrastructure/domain` | Event bus, policies, forwarding role, logging, registry, and SSM contracts |
| Contracts | `Unicorn.Contracts/Infrastructure/contracts-service` | API, queue, Lambda, DynamoDB, pipe, IAM, and logs |
| Contracts | `Unicorn.Contracts/Infrastructure/schema-registry/ContractStatusChanged` | `ContractStatusChanged` schema |
| Approvals | `Unicorn.Approvals/Infrastructure/domain` | Event bus, policies, forwarding role, logging, registry, and SSM contracts |
| Approvals | `Unicorn.Approvals/Infrastructure/approvals-service` | Lambdas, DynamoDB, Step Functions, IAM, queues, and logs |
| Approvals | `Unicorn.Approvals/Infrastructure/schema-registry/PublicationEvaluationCompleted` | `PublicationEvaluationCompleted` schema |
| Approvals | `Unicorn.Approvals/Infrastructure/subscriptions/unicorn-contracts` | Consumer-owned Contracts-to-Approvals rule |
| Approvals | `Unicorn.Approvals/Infrastructure/subscriptions/unicorn-web` | Consumer-owned Web-to-Approvals rule |
| Web | `Unicorn.Web/Infrastructure/domain` | Event bus, policies, forwarding role, logging, registry, and SSM contracts |
| Web | `Unicorn.Web/Infrastructure/web-service` | API, Lambdas, DynamoDB, queues, IAM, and logs |
| Web | `Unicorn.Web/Infrastructure/schema-registry/PublicationApprovalRequested` | `PublicationApprovalRequested` schema |
| Web | `Unicorn.Web/Infrastructure/subscriptions/approvals` | Consumer-owned Approvals-to-Web rule |
| Shared | `Unicorn.Shared/Infrastructure/api-gateway-account` | Sole account/Region owner of API Gateway account logging configuration |
| Shared | `Unicorn.Shared/Infrastructure/namespaces` | Global namespace SSM parameters |
| Shared | `Unicorn.Shared/Infrastructure/uniprop-images` | Stage image bucket and initialization resources |

Each root contains `backend.tf`, `main.tf`, `outputs.tf`, `providers.tf`, and `variables.tf`. Keep its lock file committed. Do not combine roots or introduce cross-root `terraform_remote_state` references; use the SSM operational contracts.

## Infrastructure Files

- Contracts and Web REST API definitions live in their service roots as `api.yaml.tpl`. Terraform supplies resource names and ARNs to `templatefile(...)` and assigns the rendered OpenAPI document to API Gateway.
- Approvals workflow definition lives in `PropertyApproval.asl.json`. Terraform supplies table, bucket, bus, service, and Lambda values when rendering it.
- Schema directories are Terraform roots, not deployable schema YAML stacks.
- Subscription directories are Terraform roots owned by the consuming service.
- Service `samconfig.toml` files contain build settings only. They do not contain SAM deployment configuration. Web keeps `parallel = false` because its projects share build output.
- Terraform service roots expose `sam_metadata_*` resources for the native SAM Terraform hook.

## SSM Operational Contracts

Roots exchange names and ARNs through SSM Parameter Store:

- Global namespaces: `/uni-prop/UnicornContractsNamespace`, `/uni-prop/UnicornApprovalsNamespace`, and `/uni-prop/UnicornWebNamespace`.
- Stage-scoped domain contracts under `/uni-prop/${stage}/`: `{Service}EventBus`, `{Service}EventBusArn`, `{Service}SchemaRegistryName`, and `{Service}EventBridgeRoleArn`.
- Shared images: `/uni-prop/${stage}/ImagesBucket`.

These values are deployment contracts, not secrets. Renaming or removing a parameter is a cross-root and cross-IaC breaking change. Keep provider `namespace` default tags and event source values aligned with the global namespace parameters.

## Dependency Order and Ownership

The root `Makefile` implements the required five phases:

1. Bootstrap the versioned S3 state bucket; Terraform coordinates writers with S3-native `.tflock` objects.
2. Apply Shared `api-gateway-account`, `namespaces`, and the selected stage's `uniprop-images` root.
3. Apply Contracts, Approvals, and Web domain roots.
4. Apply all schema roots, then all workload roots.
5. Apply the three consumer-owned subscription roots.

`make delete-all STAGE=<stage>` destroys stage resources in reverse dependency order. It preserves the account/Region API Gateway singleton and the state backend. The four namespace Makefiles include `common.mk` and retain component-specific targets for narrower work.

## Code and Resource Conventions

- Projects and directories are PascalCase (`ContractsService`, `PublicationManagerService`, `SearchService`).
- Handler classes describe their trigger; domain types live beside them.
- Nullable reference types are enabled; keep new code warning-free.
- Shared Web utilities live in `Unicorn.Web/Common` and `Unicorn.Web/Data`.
- Restore and build through the Makefile or solution so `Directory.Build.props` settings apply.
- Event sources use the namespace resolved from SSM; do not hardcode a different value.
- Canonical event detail types are `ContractStatusChanged`, `PublicationApprovalRequested`, and `PublicationEvaluationCompleted`.
- Catch-all EventBridge rules live in the three workload roots and remain enabled in every stage. Domain roots own event-bus service logging.
- Explicit resource, IAM role, and log-group names are intentional Terraform conventions documented in `PARITY.md`.

## Testing Conventions

```text
<Name>Service.Test(s)/
├── <Handler>Test.cs         # xUnit tests with NSubstitute mocks
├── TestHelpers.cs           # Shared fixtures and helpers
└── events/                  # Sample event payloads
```

Use `[action]_[entity]_[condition]_[n].json` for test event names. Run service tests with `make test`; coverage is collected through coverlet.

## Development Workflow

When adding a feature:

1. Implement the handler in the owning Lambda project following existing patterns.
2. Add or update resources in the owning Terraform root. Do not recreate deleted SAM deployment templates.
3. For REST changes, update the owning `api.yaml.tpl`; for approval workflow changes, update `PropertyApproval.asl.json`.
4. Add sample event payloads and tests beside the existing tests.
5. If the change publishes or consumes an event, update the owning schema and consumer subscription roots while preserving SSM contracts and deployment order.
6. Run `make lint`, `make test`, and `python3 scripts/validate_infrastructure.py --checkov` before deployment. Use `make deploy-all STAGE=dev` for a full ordered development deployment.

Preserve the 15-root structure unless a separately reviewed change updates state ownership, validation, orchestration, and `PARITY.md` together.
