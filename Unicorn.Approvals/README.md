# Developing Unicorn Approvals

![Properties Approval Architecture](https://static.us-east-1.prod.workshops.aws/public/f273b5fc-17cd-406b-9e63-1d331b00589d/static/images/architecture-approvals.png)

## Architecture

Unicorn Approvals uses AWS Step Functions to evaluate property listings. The workflow verifies contract state, description content, and images before publishing `PublicationEvaluationCompleted`.

A `PublicationApprovalRequested` event from Unicorn Web starts the workflow. Approvals maintains a local contract-status projection by consuming `ContractStatusChanged`, avoiding direct access to the Contracts database. When a workflow must wait for contract approval, a task token is stored with the property state; a DynamoDB stream handler resumes the execution after the contract changes.

The Lambda projects target .NET 10. Terraform is the sole deployment and state owner; AWS SAM is used only through its Terraform hook for build and local invocation. See [Infrastructure](Infrastructure/README.md) for root ownership and cross-service dependencies.

## Event contracts

All event `detail` properties use PascalCase.

Approvals consumes `ContractStatusChanged` with required `PropertyId`, `ContractId`, `ContractStatus`, and `ContractLastModifiedOn`. It also consumes `PublicationApprovalRequested` with this shape:

```json
{
  "PropertyId": "usa/anytown/main-street/123",
  "Status": "PENDING",
  "Address": {
    "Country": "USA",
    "City": "Anytown",
    "Street": "Main Street",
    "Number": "123"
  },
  "Description": "A classic Anytown estate with a lake view.",
  "Images": [
    "property_images/prop1_exterior1.jpg",
    "property_images/prop1_interior1.jpg"
  ]
}
```

Approvals publishes `PublicationEvaluationCompleted`:

```json
{
  "PropertyId": "usa/anytown/main-street/123",
  "EvaluationResult": "APPROVED"
}
```

`PropertyId` and `EvaluationResult` are required. The authoritative producer schema is [`Infrastructure/schema-registry/PublicationEvaluationCompleted`](Infrastructure/schema-registry/PublicationEvaluationCompleted/).

## Commands

Run commands from `Unicorn.Approvals`:

```bash
make test
make build STAGE=local
make local-invoke STAGE=local
make plan STAGE=local
make deploy STAGE=dev
make plan-sub-contracts STAGE=local
make plan-sub-web STAGE=local
```

`make build` runs `sam build --hook-name terraform` in `Infrastructure/approvals-service`. `make local-invoke` defaults to `aws_lambda_function.contract_status_changed_handler` and uses `sam local invoke --hook-name terraform ... --skip-prepare-infra`; override the address with `FUNCTION=...`.

For `prod`, create and review each root's `.terraform/prod.tfplan` with `make plan STAGE=prod`, then apply those exact plans with `make deploy STAGE=prod CONFIRM_PROD=APPLY`. Production deletion requires `CONFIRM_PROD=DESTROY`. Stop any running approval workflow executions before intentionally removing the service root.
