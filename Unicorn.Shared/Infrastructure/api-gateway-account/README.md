# API Gateway account logging

This Terraform root owns the single API Gateway CloudWatch logging configuration for one AWS account and Region. Deploy it before the Contracts or Web service roots. It is intentionally independent of the `local`, `dev`, and `prod` service stages because `aws_api_gateway_account` is account- and Region-scoped.

Do not apply this root until any existing Contracts or Web ownership has been reconciled. Import the existing API Gateway account configuration into this state before removing it from another state:

```bash
terraform import aws_api_gateway_account.main api-gateway-account
```

The IAM role may also be imported if an existing role is selected for reuse; otherwise review the plan for a deliberate role replacement. Never allow multiple Terraform states to manage `aws_api_gateway_account` in the same account and Region.
