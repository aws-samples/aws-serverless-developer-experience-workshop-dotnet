# Unicorn Web infrastructure

Terraform is the sole deployment and state owner. AWS SAM is only a build/local-test client for Terraform-defined Lambda functions.

## Independent roots

| Root                                                                                            | Owns                                                                                      | Depends on                                                                                    |
| ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| [`domain`](domain/)                                                                             | Web event bus, policies, forwarding role, logging, schema registry, and stage SSM exports | Shared global Web namespace                                                                   |
| [`schema-registry/PublicationApprovalRequested`](schema-registry/PublicationApprovalRequested/) | One `PublicationApprovalRequested` schema                                                 | Web domain registry SSM parameter                                                             |
| [`web-service`](web-service/)                                                                   | API Gateway, DynamoDB, queues, three .NET 10 Lambdas, IAM, event trigger, and logs        | Web and Approvals namespaces, Web event bus, and Shared API Gateway account logging singleton |
| [`subscriptions/approvals`](subscriptions/approvals/)                                           | Consumer-owned `PublicationEvaluationCompleted` forwarding rule on the Approvals bus      | Approvals and Web domains                                                                     |

These roots intentionally separate domain, schema, workload, and consumer-owned subscription state. The subscription is owned by Web because Web consumes the event, even though its rule is created on the Approvals bus.

## Event and SSM contracts

The domain consumes `/uni-prop/UnicornWebNamespace` and publishes stage-scoped `WebEventBus`, `WebEventBusArn`, `WebSchemaRegistryName`, and `WebEventBridgeRoleArn` parameters. The service also consumes `/uni-prop/UnicornApprovalsNamespace`.

All event details use PascalCase. `PublicationApprovalRequested` requires `PropertyId`, `Status`, `Description`, `Images`, and `Address`; `Address` requires string fields `Country`, `City`, `Street`, and `Number`. `PublicationEvaluationCompleted` requires `PropertyId` and `EvaluationResult`.

These SSM names and event shapes are intentional external contracts. Apply Shared infrastructure first, then Web and Approvals domains, then schema and service roots. Apply the Approvals subscription last. Destroy in reverse order.

## Workflow

Run from `Unicorn.Web`:

```bash
make ensure-state-backend
make init STAGE=local
make plan STAGE=local
make deploy STAGE=local
make test
make lint
```

Component targets include domain, schema, service, and Approvals subscription `init-*`, `plan-*`, and `deploy-*` variants.

`make build` uses the native Terraform hook in `Infrastructure/web-service`; `make local-invoke` defaults to Search:

```bash
sam build --hook-name terraform
sam local invoke --hook-name terraform aws_lambda_function.search_function --skip-prepare-infra
```

For `STAGE=prod`, each root writes `.terraform/prod.tfplan`. Review every saved plan immediately before applying it with `CONFIRM_PROD=APPLY`. Production deletion requires `CONFIRM_PROD=DESTROY`.

Lambda packaging uses [`../../scripts/package_dotnet_lambda.py`](../../scripts/package_dotnet_lambda.py) for deterministic Release ZIPs. Keep each root's `.terraform.lock.hcl` committed. Validate all 15 roots from the repository root:

```bash
python3 scripts/validate_infrastructure.py
```
