terraform {
  backend "s3" {
    # Backend configuration is provided by the Makefile via -backend-config flags.
    # Example: terraform init -backend-config="bucket=my-terraform-state" -backend-config="key=uni-prop-{stage}-contracts-schema.tfstate"
  }
}
