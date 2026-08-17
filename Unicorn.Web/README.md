# Developing Unicorn Web

![Properties Web Architecture](https://static.us-east-1.prod.workshops.aws/public/f273b5fc-17cd-406b-9e63-1d331b00589d/static/images/architecture-properties-web.png)

## Architecture

Unicorn Web lets customers search approved property listings and lets agents request publication approval.

- The Search Lambda serves property searches and details from DynamoDB.
- API Gateway queues approval requests in Amazon SQS; the Request Approval Lambda publishes `PublicationApprovalRequested`.
- The Publication Evaluation Event Handler consumes `PublicationEvaluationCompleted` from Unicorn Approvals and updates the listing's publication result.

The Lambda projects target .NET 10. Terraform is the sole deployment and state owner; AWS SAM is used only through its Terraform hook for build and local invocation. See [Infrastructure](Infrastructure/README.md) for root ownership and dependencies.

## Event contracts

All event `detail` properties use PascalCase. Web publishes `PublicationApprovalRequested` with exactly these required fields:

```json
{
  "PropertyId": "usa/anytown/main-street/123",
  "Status": "PENDING",
  "Description": "A classic Anytown estate with a lake view.",
  "Images": [
    "property_images/prop1_exterior1.jpg",
    "property_images/prop1_interior1.jpg"
  ],
  "Address": {
    "Country": "USA",
    "City": "Anytown",
    "Street": "Main Street",
    "Number": "123"
  }
}
```

The required top-level fields are `PropertyId`, `Status`, `Description`, `Images`, and `Address`; `Address` requires `Country`, `City`, `Street`, and `Number`, all strings. The authoritative schema is [`Infrastructure/schema-registry/PublicationApprovalRequested`](Infrastructure/schema-registry/PublicationApprovalRequested/).

Web consumes `PublicationEvaluationCompleted` with required `PropertyId` and `EvaluationResult`:

```json
{
  "PropertyId": "usa/anytown/main-street/123",
  "EvaluationResult": "APPROVED"
}
```

## Commands

Run commands from `Unicorn.Web`:

```bash
make test
make build STAGE=local
make local-invoke STAGE=local
make plan STAGE=local
make deploy STAGE=dev
make plan-sub-approvals STAGE=local
```

`make build` runs `sam build --hook-name terraform` in `Infrastructure/web-service`. `make local-invoke` defaults to `aws_lambda_function.search_function` and uses `sam local invoke --hook-name terraform ... --skip-prepare-infra`; override the address with `FUNCTION=...`.

For `prod`, create and review each root's `.terraform/prod.tfplan` with `make plan STAGE=prod`, then apply those exact plans with `make deploy STAGE=prod CONFIRM_PROD=APPLY`. Production deletion requires `CONFIRM_PROD=DESTROY`.
