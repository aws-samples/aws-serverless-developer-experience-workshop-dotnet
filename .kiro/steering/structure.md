# Project Structure & Conventions

## Repository Layout

Multi-service monorepo with three services plus shared infrastructure:

```text
├── Unicorn.Contracts/      # Contracts Service - property contracts
├── Unicorn.Approvals/      # Approvals Service - approval workflow
├── Unicorn.Web/            # Web Service - property listings and search
├── Unicorn.Shared/         # Global namespaces and shared images stacks
├── docs/                   # Documentation and architecture diagrams
├── UnicornProperties.sln   # Solution referencing all projects
├── Directory.Build.props   # Shared MSBuild settings
└── global.json             # .NET SDK version pin
```

## Service Structure Pattern

Each service follows this structure. Maintain it when adding or modifying services:

```text
Unicorn.<Service>/
├── Makefile                     # Canonical build/deploy/test interface
├── <Name>Service/               # Lambda project (PascalCase)
│   ├── <Name>Service.csproj     # Dependencies (packages.lock.json committed)
│   └── *.cs                     # Handlers and domain types
├── <Name>Service.Test(s)/       # xUnit test project
│   ├── *.cs                     # Tests and helpers
│   └── events/                  # Sample event payloads
└── Infrastructure/              # All IaC for the service (see below)
```

`Unicorn.Web` contains multiple projects (`PublicationManagerService`, `SearchService`, plus `Common` and `Data`). Step Functions ASL definitions live next to the service template (e.g., `Unicorn.Approvals/Infrastructure/approvals-service/PropertyApproval.asl.yaml`).

## Infrastructure Layout

Every service owns its infrastructure under `Infrastructure/`:

```text
Infrastructure/
├── domain.yaml                     # Event bus, bus policies, schema registry,
│                                   #   catch-all rule, SSM exports
├── <service>-service/
│   ├── template.yaml               # Lambda, API Gateway, DynamoDB, queues
│   ├── samconfig.toml              # SAM build/deploy configuration
│   └── api.yaml                    # OpenAPI specification (REST services)
├── schema-registry/
│   └── <EventName>-schema.yaml     # One stack per published event schema
└── subscriptions/
    └── <producer>-subscriptions.yaml  # Rules on producer buses feeding this service
```

Deploy order: shared namespaces first, then per service `domain -> schema -> service`; subscriptions reference both participating domains. `make deploy` and `make delete` encode the correct (reverse) order.

## Code Conventions

- Projects and directories are PascalCase (`ContractsService`, `PublicationManagerService`, `SearchService`)
- Handler classes describe the trigger (`ContractEventHandler.cs`); domain types live beside them (`Contract.cs`, `ContractStatus.cs`)
- Nullable reference types are enabled; keep new code warning-free
- Shared Web utilities live in `Unicorn.Web/Common` and `Unicorn.Web/Data`
- Restore/build through the Makefile or solution so `Directory.Build.props` settings apply

## Resource Naming & Events

- Stack names: `uni-prop-{stage}-{service}` (e.g., `uni-prop-local-contracts`); schema stacks append `-schema-<EventName>`
- Event buses: `unicorn-{service}-eventbus-${Stage}` (e.g., `unicorn-contracts-eventbus-local`), exported via SSM
- Event sources use the service namespace value (e.g., `unicorn-contracts`), resolved from the SSM namespace parameters — never hardcode it
- Canonical event detail types: `ContractStatusChanged` (Contracts), `PublicationApprovalRequested` (Web), `PublicationEvaluationCompleted` (Approvals)
- SSM parameter contracts:
  - Global namespaces: `/uni-prop/Unicorn{Service}Namespace`
  - Stage-scoped: `/uni-prop/${Stage}/{Service}EventBus`, `...EventBusArn`, `...SchemaRegistryName`
- Each domain template includes a catch-all rule logging all bus events to CloudWatch for debugging

## Testing Conventions

```text
<Name>Service.Test(s)/
├── <Handler>Test.cs         # xUnit tests, NSubstitute mocks
├── TestHelpers.cs           # Shared fixtures/helpers
└── events/                  # Sample event payloads (e.g., create_contract_valid_1.json)
```

- Test event naming: `[action]_[entity]_[condition]_[n].json` (e.g., `create_contract_valid_1.json`)
- Run tests with `make test` (wraps `dotnet test`); coverage collected via coverlet

## Development Workflow

When adding a feature:

1. Implement the handler in the service's Lambda project following existing patterns
2. Add or update SAM resources in `Infrastructure/<service>-service/template.yaml` using the naming conventions above
3. Add sample event payloads under the test project's `events/` and tests beside existing ones
4. If the change publishes or consumes a new event: update `Infrastructure/schema-registry/` and the consumer's `Infrastructure/subscriptions/`
5. Run `make lint` and `make test` before deploying with `make deploy STAGE=local`

When modifying services, preserve the existing structure — do not reorganize directories without a documented reason.
