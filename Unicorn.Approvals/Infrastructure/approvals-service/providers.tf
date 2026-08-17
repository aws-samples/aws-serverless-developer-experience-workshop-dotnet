# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

terraform {
  required_version = ">= 1.6, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region                      = var.region
  skip_credentials_validation = var.sam_build
  skip_metadata_api_check     = var.sam_build
  skip_region_validation      = var.sam_build
  skip_requesting_account_id  = var.sam_build

  default_tags {
    tags = {
      stage     = var.stage
      project   = "AWS Serverless Developer Experience"
      namespace = "unicorn-approvals"
    }
  }
}
