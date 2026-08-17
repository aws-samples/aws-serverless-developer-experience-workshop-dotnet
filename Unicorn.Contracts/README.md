# Developing Unicorn Contracts

![Contracts Service Architecture](https://static.us-east-1.prod.workshops.aws/public/f273b5fc-17cd-406b-9e63-1d331b00589d/static/images/architecture-contracts.png)

## Architecture

Unicorn Contracts manages contractual relationships between property sellers and Unicorn Properties, including terms, service rates, fees, and additional services. A property address is its cross-service identifier, for example `usa/anytown/main-street/111`, and each property can have only one active contract.

1. Agents submit create or update requests through API Gateway.
2. API Gateway sends requests to Amazon SQS.
3. the Contracts Lambda updates Amazon DynamoDB.
4. DynamoDB Streams and EventBridge Pipes publish `ContractStatusChanged` to the Contracts event bus.
5. Unicorn Approvals consumes the event without direct access to the Contracts table.

The Lambda project targets .NET 10. Terraform is the sole deployment and state owner; AWS SAM is used only through its Terraform hook for build and local invocation. See [Infrastructure](Infrastructure/README.md) for root ownership and dependencies.

## Event contract

Event `detail` fields use .NET-style PascalCase. The canonical `ContractStatusChanged` shape is:

```json
{
  "version": "0",
  "account": "123456789012",
  "region": "us-east-1",
  "detail-type": "ContractStatusChanged",
  "source": "unicorn-contracts",
  "time": "2022-08-14T22:06:31Z",
  "id": "c071bfbf-83c4-49ca-a6ff-3df053957145",
  "resources": [],
  "detail": {
    "PropertyId": "usa/anytown/main-street/111",
    "ContractId": "617dda8c-e79b-406a-bc5b-3a4712f5e4d7",
    "ContractStatus": "DRAFT",
    "ContractLastModifiedOn": "2022-08-14T22:06:31Z"
  }
}
```

`PropertyId`, `ContractId`, `ContractStatus`, and `ContractLastModifiedOn` are required. The Terraform schema at [`Infrastructure/schema-registry/ContractStatusChanged`](Infrastructure/schema-registry/ContractStatusChanged/) is authoritative.

## Commands

Run commands from `Unicorn.Contracts`:

```bash
make test
make build STAGE=local
make local-invoke STAGE=local
make plan STAGE=local
make deploy STAGE=dev
```

`make build` runs `sam build --hook-name terraform` in `Infrastructure/contracts-service`. `make local-invoke` runs `sam local invoke --hook-name terraform aws_lambda_function.contract_event_handler --skip-prepare-infra`; override the address with `FUNCTION=...`.

For `prod`, first run and review `make plan STAGE=prod`, which saves one plan per root at `.terraform/prod.tfplan`. Apply only that reviewed plan with `make deploy STAGE=prod CONFIRM_PROD=APPLY`. Production deletion requires `CONFIRM_PROD=DESTROY`.
