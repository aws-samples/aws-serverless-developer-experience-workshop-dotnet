terraform {
  backend "s3" {
    # Backend configuration should be provided via backend config file or CLI
    # Example: terraform init -backend-config="bucket=my-terraform-state" -backend-config="key=uni-prop-{stage}-approvals-schema-PublicationEvaluationCompleted.tfstate"
  }
}








