# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

output "image_upload_bucket_name" {
  description = "S3 bucket for property images"
  value       = aws_s3_bucket.unicorn_properties_images.bucket
}
