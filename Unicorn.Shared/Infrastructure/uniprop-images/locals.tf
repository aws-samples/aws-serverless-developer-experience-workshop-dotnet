# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

locals {
  is_prod     = var.stage == "prod"
  bucket_name = "uni-prop-${var.stage}-images-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
}
