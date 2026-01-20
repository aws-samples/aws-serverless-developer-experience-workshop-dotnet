terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  backend "s3" {
    # Backend configuration should be provided via backend config file or CLI
    # Example: terraform init -backend-config="bucket=my-terraform-state" -backend-config="key=uni-prop-namespaces.tfstate"
  }
}

provider "aws" {
  region = var.region
}

resource "aws_ssm_parameter" "unicorn_contracts_namespace" {
  name  = "/uni-prop/UnicornContractsNamespace"
  type  = "String"
  value = "unicorn-contracts"
  tags = {
    project = "AWS Serverless Developer Experience"
    service = "Unicorn Base Infrastructure"
  }
}

resource "aws_ssm_parameter" "unicorn_approvals_namespace" {
  name  = "/uni-prop/UnicornApprovalsNamespace"
  type  = "String"
  value = "unicorn-approvals"
  tags = {
    project = "AWS Serverless Developer Experience"
    service = "Unicorn Base Infrastructure"
  }
}

resource "aws_ssm_parameter" "unicorn_web_namespace" {
  name  = "/uni-prop/UnicornWebNamespace"
  type  = "String"
  value = "unicorn-web"
  tags = {
    project = "AWS Serverless Developer Experience"
    service = "Unicorn Base Infrastructure"
  }
}



