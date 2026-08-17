# Unicorn Contracts infrastructure

Terraform is the sole deployment and state owner. AWS SAM is only a build/local-test client for Terraform-defined Lambda functions.

## Independent roots

| Root                                                                              | Owns                                                                                                      | Depends on                                                                                     |
| --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| [`domain`](domain/)                                                               | Contracts event bus, event-bus policies, forwarding role, logging, schema registry, and stage SSM exports | Shared global Contracts namespace                                                              |
| [`schema-registry/ContractStatusChanged`](schema-registry/ContractStatusChanged/) | One `ContractStatusChanged` schema                                                                        | Contracts domain registry SSM parameter                                                        |
| [`contracts-service`](contracts-service/)                                         | API Gateway, SQS and DLQ, .NET 10 Lambda, DynamoDB and stream, EventBridge Pipe, IAM, and logs            | Contracts namespace and event-bus SSM parameters; Shared API Gateway account logging singleton |

These roots intentionally keep domain, schema, and workload lifecycles in separate state. The service root is `contracts-service`; it does not own the domain event bus or schema registry.

## Event and SSM contracts

The domain consumes `/uni-prop/UnicornContractsNamespace` and publishes these stage-scoped parameters:

- `/uni-prop/${stage}/ContractsEventBus`
- `/uni-prop/${stage}/ContractsEventBusArn`
- `/uni-prop/${stage}/ContractsSchemaRegistryName`
- `/uni-prop/${stage}/ContractsEventBridgeRoleArn`

The service's EventBridge Pipe emits PascalCase `ContractStatusChanged` details: `PropertyId`, `ContractId`, `ContractStatus`, and `ContractLastModifiedOn`. The schema root enforces the same required fields. SSM names are intentional external contracts; coordinate any change across dependent roots.

Apply Shared account/Region infrastructure and namespaces first, then Contracts `domain`, schema, and service in that order. Apply the Approvals Contracts subscription only after both Contracts and Approvals domains exist. Destroy in reverse order.

## Workflow

Run from `Unicorn.Contracts`:

```bash
make ensure-state-backend
make init STAGE=local
make plan STAGE=local
make deploy STAGE=local
make test
make lint
```

Component targets include `init-domain`, `init-schema`, `init-service`, corresponding `plan-*` and `deploy-*` targets, and reverse-order `delete`.

`make build` restores the projects and runs the native Terraform hook in `Infrastructure/contracts-service`:

```bash
sam build --hook-name terraform
sam local invoke --hook-name terraform aws_lambda_function.contract_event_handler --skip-prepare-infra
```

The Makefile supplies `TF_VAR_stage` and `TF_VAR_region`; prefer `make build` and `make local-invoke` so those values are consistent.

For `STAGE=prod`, every root plan is saved as `.terraform/prod.tfplan`. Review each plan immediately before applying it with `CONFIRM_PROD=APPLY`. Production deletion requires `CONFIRM_PROD=DESTROY`.

Lambda packaging uses [`../../scripts/package_dotnet_lambda.py`](../../scripts/package_dotnet_lambda.py) for deterministic Release ZIPs. Keep each root's `.terraform.lock.hcl` committed. Validate the repository from its root with:

```bash
python3 scripts/validate_infrastructure.py
```
