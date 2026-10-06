# Unicorn Shared infrastructure

Unicorn Shared owns infrastructure that cannot belong safely to one business service. Terraform is the sole deployment and state owner.

## Independent roots

| Root                                                                        | Scope and ownership                                                                                                        |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| [`Infrastructure/api-gateway-account`](Infrastructure/api-gateway-account/) | Sole owner of `aws_api_gateway_account`, its CloudWatch logging role, and policy attachment for one AWS account and Region |
| [`Infrastructure/namespaces`](Infrastructure/namespaces/)                   | Global, non-stage SSM parameters for the Contracts, Approvals, and Web event-source namespaces                             |
| [`Infrastructure/uniprop-images`](Infrastructure/uniprop-images/)           | Stage-scoped shared image bucket, `/uni-prop/${stage}/ImagesBucket`, and image initialization resources                    |

The API Gateway account settings are an account/Region singleton. A second root must never manage the same `aws_api_gateway_account`. Its backend key includes the Region, and the aggregate `make delete` intentionally leaves it in place. Review singleton changes as account-wide changes even though this root is not stage-scoped.

The namespace root publishes these intentional external operational contracts:

- `/uni-prop/UnicornContractsNamespace`
- `/uni-prop/UnicornApprovalsNamespace`
- `/uni-prop/UnicornWebNamespace`

Domain, service, schema, and subscription roots read these values. The images root publishes `/uni-prop/${stage}/ImagesBucket`, consumed by Approvals. Rename or remove parameters only as a coordinated cross-root breaking change.

## Deployment order

1. Bootstrap the state backend once with `make ensure-state-backend`.
2. Apply `api-gateway-account` and `namespaces`.
3. Apply `uniprop-images` for each needed stage.
4. Apply service domains, schemas, workloads, and subscriptions in their documented order.

On teardown, remove subscriptions, workloads, schemas, and domains before Shared parameters. `make delete` removes images and account-global namespaces but deliberately does not remove the API Gateway account singleton. It requires `CONFIRM_PROD=DESTROY` for production images and the independent `CONFIRM_ACCOUNT_GLOBAL=DESTROY` token for namespace removal because those parameters are used by every stage.

## Commands

Run from `Unicorn.Shared`:

```bash
make init
make plan
# Applies the account singleton, global namespaces, and local/dev/prod image roots;
# review the production saved plan before applying it
make deploy CONFIRM_PROD=APPLY
make describe

# Aggregate deletion requires separate production and account-global confirmations
make delete CONFIRM_PROD=DESTROY CONFIRM_ACCOUNT_GLOBAL=DESTROY

# Component and stage examples are preferable for a narrower scope
make init-images-local
make plan-api-gateway-account
make plan-namespaces
make plan-images-local
make deploy-images-dev
```

`local`, `dev`, and `prod` are separate states for `uniprop-images`, but they share one Terraform working directory. Use the matching `init-images-local`, `init-images-dev`, or `init-images-prod` target before direct Terraform work so the directory points to the intended backend key. Aggregate `make init` runs sequentially and re-initializes `local` last, leaving the working directory on the safe local state.

Production image planning saves `Infrastructure/uniprop-images/.terraform/prod.tfplan`; review it immediately and use `CONFIRM_PROD=APPLY` to apply that exact plan. Production image deletion requires `CONFIRM_PROD=DESTROY`. The API Gateway account singleton and global namespace root use `shared` scope rather than a stage and are not covered by the production-stage gate. Deleting namespaces directly or through aggregate deletion requires `CONFIRM_ACCOUNT_GLOBAL=DESTROY`.

Every root has a committed `.terraform.lock.hcl`. Validate all 15 repository roots from the repository root:

```bash
python3 scripts/validate_infrastructure.py --checkov
```
