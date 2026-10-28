# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

variable "stage" {
  description = "Deployment stage (local, dev, prod)"
  type        = string

  validation {
    condition     = contains(["local", "dev", "prod"], var.stage)
    error_message = "Stage must be one of: local, dev, prod."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
}
