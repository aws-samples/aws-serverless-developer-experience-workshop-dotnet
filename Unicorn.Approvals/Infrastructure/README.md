# Unicorn Approvals infrastructure

Terraform is the sole deployment and state owner. AWS SAM is only a build/local-test client for Terraform-defined Lambda functions.

## Independent roots

| Root                                                                                                | Owns                                                                                            | Depends on                                                                |
| --------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| [`domain`](domain/)                                                                                 | Approvals event bus, policies, forwarding role, logging, schema registry, and stage SSM exports | Shared global Approvals namespace                                         |
| [`schema-registry/PublicationEvaluationCompleted`](schema-registry/PublicationEvaluationCompleted/) | One `PublicationEvaluationCompleted` schema                                                     | Approvals domain registry SSM parameter                                   |
| [`approvals-service`](approvals-service/)                                                           | Three .NET 10 Lambdas, DynamoDB and stream, Step Functions, DLQs, IAM, event trigger, and logs  | All global namespaces, Approvals bus, Shared images, and domain resources |
| [`subscriptions/unicorn-contracts`](subscriptions/unicorn-contracts/)                               | Consumer-owned `ContractStatusChanged` forwarding rule on the Contracts bus                     | Contracts and Approvals domains                                           |
| [`subscriptions/unicorn-web`](subscriptions/unicorn-web/)                                           | Consumer-owned `PublicationApprovalRequested` forwarding rule on the Web bus                    | Web and Approvals domains                                                 |

The five roots preserve separate domain, workload, schema, and consumer-owned subscription lifecycles. Subscription roots intentionally configure rules on producer buses while forwarding through the Approvals domain role.

## Event and SSM contracts

The domain consumes `/uni-prop/UnicornApprovalsNamespace` and publishes stage-scoped `ApprovalsEventBus`, `ApprovalsEventBusArn`, `ApprovalsSchemaRegistryName`, and `ApprovalsEventBridgeRoleArn` parameters. The service also consumes the Contracts and Web namespace parameters and `/uni-prop/${stage}/ImagesBucket`.

All event details use PascalCase:

- `ContractStatusChanged`: `PropertyId`, `ContractId`, `ContractStatus`, `ContractLastModifiedOn`.
- `PublicationApprovalRequested`: `PropertyId`, `Status`, `Description`, `Images`, and `Address`; `Address` requires `Country`, `City`, `Street`, and `Number`.
- `PublicationEvaluationCompleted`: required `PropertyId` and `EvaluationResult`.

These SSM names and event shapes are intentional external contracts. Apply Shared infrastructure first; apply all participating domains before schemas and workloads; apply subscriptions last. Destroy subscriptions before services, schemas, and domains.

## Workflow

Run from `Unicorn.Approvals`:

```bash
make ensure-state-backend
make init STAGE=local
make plan STAGE=local
make deploy STAGE=local
make test
make lint
```

Component targets include domain, schema, service, Contracts subscription, and Web subscription `init-*`, `plan-*`, and `deploy-*` variants.

`make build` uses the native Terraform hook in `Infrastructure/approvals-service`; `make local-invoke` defaults to the contract-status handler:

```bash
sam build --hook-name terraform
sam local invoke --hook-name terraform aws_lambda_function.contract_status_changed_handler --skip-prepare-infra
```

For `STAGE=prod`, each root writes `.terraform/prod.tfplan`. Review every saved plan immediately before applying it with `CONFIRM_PROD=APPLY`. Production deletion requires `CONFIRM_PROD=DESTROY`.

Lambda packaging uses [`../../scripts/package_dotnet_lambda.py`](../../scripts/package_dotnet_lambda.py) for deterministic Release ZIPs. Keep each root's `.terraform.lock.hcl` committed. Validate all 15 roots from the repository root:

```bash
python3 scripts/validate_infrastructure.py
```
