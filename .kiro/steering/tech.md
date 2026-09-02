# Technology Stack & Build System

## Runtime & Language

- **.NET 10** (`net10.0` target framework; SDK pinned in `global.json`) - all Lambda functions
- **dotnet CLI** with a repository solution (`UnicornProperties.sln`) and shared build settings in `Directory.Build.props`
- **AWS SAM** - infrastructure as code, build, and deployment

## AWS Services

- **AWS Lambda** - serverless compute
- **Amazon DynamoDB** - NoSQL persistence with streams
- **Amazon EventBridge** - event bus, schema registry, and cross-service messaging
- **AWS Step Functions** - approval workflow orchestration
- **Amazon API Gateway** - REST API endpoints
- **Amazon SQS** - ingest queues and dead-letter queues
- **AWS X-Ray** - distributed tracing
- **Amazon CloudWatch** - logging, metrics, and monitoring

## Key Libraries & Frameworks

- **AWS Lambda Powertools for .NET** (`AWS.Lambda.Powertools.Logging`, `Metrics`, `Tracing`) - structured logging, metrics, and tracing
- **AWS SDK for .NET** (`AWSSDK.DynamoDBv2`, etc.) with `Amazon.Lambda.*` events and serialization packages
- **xUnit** with `Amazon.Lambda.TestUtilities`, **NSubstitute** for mocking, and `coverlet` for coverage
- NuGet lock files (`packages.lock.json`) are committed per project

## Build & Development Commands

### Make Targets (canonical interface)

Run from a service directory (e.g., `Unicorn.Contracts/`). Stages: `local` (default), `dev`, `prod`; default region `ap-southeast-2`.

```bash
make build STAGE=local      # dotnet restore/build, then sam build
make deploy STAGE=local     # deploy-domain + deploy-schema + deploy-service
make deploy-domain          # Event bus, schema registry (Infrastructure/domain.yaml)
make deploy-schema          # Event schema stack(s)
make deploy-service         # Lambda, API Gateway, DynamoDB (service template)
make test                   # dotnet test (xUnit)
make lint                   # cfn-lint all infrastructure templates
make clean                  # Remove .aws-sam/ and dotnet clean
make delete                 # Delete stacks in reverse dependency order
```

`Unicorn.Shared/` has its own targets: `deploy-namespaces`, `deploy-images` (per-stage variants), `deploy`, `list-parameters`, and reverse-order `delete` targets. Deploy shared namespaces before any service.

### Runtime Commands

Inside a service directory, the make targets invoke dotnet commands you can also run directly:

```bash
dotnet restore <Service>/<Service>.csproj      # Restore dependencies
dotnet build <Service>/<Service>.csproj       # Compile
dotnet test <Service>.Test/<Service>.Tests.csproj  # Run xUnit tests
dotnet clean                                   # Clean build outputs
```

### SAM Commands

```bash
sam build --cached --parallel                  # Build (config in samconfig.toml)
sam deploy --no-confirm-changeset              # Deploy current service
sam validate --lint                            # Validate templates
sam sync --watch                               # Rapid dev iteration
sam local start-api --warm-containers EAGER    # Local API
sam local start-lambda --warm-containers EAGER # Local Lambda endpoint
```

`samconfig.toml` in each `Infrastructure/<service>-service/` directory sets stack name, cached/parallel builds, `disable_rollback` for dev iteration, and `Stage` parameter overrides.

## Environment Variables

Standard Lambda environment variables set in the SAM templates:

- `DYNAMODB_TABLE` - DynamoDB table name
- `SERVICE_NAMESPACE` - service identifier for event sources (from SSM namespace parameters)
- `POWERTOOLS_SERVICE_NAME`, `POWERTOOLS_METRICS_NAMESPACE` - Powertools identifiers
- `POWERTOOLS_LOG_LEVEL`, `POWERTOOLS_LOGGER_CASE`, `POWERTOOLS_LOGGER_LOG_EVENT`, `POWERTOOLS_LOGGER_SAMPLE_RATE`, `POWERTOOLS_TRACE_DISABLED` - observability tuning (stage-mapped)
- `LOG_LEVEL` - application log level
