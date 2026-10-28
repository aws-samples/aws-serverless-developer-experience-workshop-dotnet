# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Stage-scoped property image bucket (deployment phase 2: shared).
#
# Creates the hardened image bucket, publishes its name to
# /uni-prop/<stage>/ImagesBucket for the Approvals workflow, and invokes a one-off
# Lambda function (lambda/image_upload.py) that seeds the bucket with sample
# property images, mirroring the SAM custom resource.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

resource "aws_s3_bucket" "unicorn_properties_images" {
  bucket = local.bucket_name

  # CFN parity: the SAM stack emptied and removed the bucket on stack delete.
  # Terraform empties the bucket on destroy; production keeps manual cleanup as a safeguard.
  force_destroy = !local.is_prod
}

resource "aws_s3_bucket_public_access_block" "unicorn_properties_images" {
  bucket = aws_s3_bucket.unicorn_properties_images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "unicorn_properties_images" {
  bucket = aws_s3_bucket.unicorn_properties_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "unicorn_properties_images" {
  bucket = aws_s3_bucket.unicorn_properties_images.id

  versioning_configuration {
    status = local.is_prod ? "Enabled" : "Suspended"
  }
}

resource "aws_ssm_parameter" "unicorn_properties_images_bucket" {
  name  = "/uni-prop/${var.stage}/ImagesBucket"
  type  = "String"
  value = aws_s3_bucket.unicorn_properties_images.bucket
}

data "archive_file" "image_upload_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/image_upload.py"
  output_path = "${path.module}/lambda/image_upload.zip"
}

resource "aws_iam_role" "image_upload_lambda_role" {
  name = "uni-prop-${var.stage}-image-upload-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "image_upload_lambda_policy" {
  name = "uni-prop-${var.stage}-image-upload-lambda-policy"
  role = aws_iam_role.image_upload_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.unicorn_properties_images.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/uni-prop-${var.stage}-image-upload:*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "image_upload" {
  filename      = data.archive_file.image_upload_lambda.output_path
  function_name = "uni-prop-${var.stage}-image-upload"
  role          = aws_iam_role.image_upload_lambda_role.arn
  handler       = "image_upload.lambda_handler"
  runtime       = "python3.13"
  timeout       = 15
  memory_size   = 512
  architectures = ["arm64"]
  tracing_config {
    mode = "Active"
  }

  source_code_hash = data.archive_file.image_upload_lambda.output_base64sha256
}

resource "aws_cloudwatch_log_group" "image_upload_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.image_upload.function_name}"
  retention_in_days = var.stage == "prod" ? 14 : 3
}

resource "aws_lambda_invocation" "image_upload" {
  function_name = aws_lambda_function.image_upload.function_name

  input = jsonencode({
    RequestType = "Create"
    ResourceProperties = {
      DestinationBucket = aws_s3_bucket.unicorn_properties_images.bucket
    }
  })

  depends_on = [
    aws_lambda_function.image_upload,
    aws_s3_bucket.unicorn_properties_images,
    aws_cloudwatch_log_group.image_upload_lambda
  ]
}
