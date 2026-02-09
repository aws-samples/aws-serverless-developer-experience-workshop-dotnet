data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_s3_bucket" "unicorn_properties_images" {
  bucket = local.bucket_name
  tags   = local.common_tags
}

resource "aws_ssm_parameter" "unicorn_properties_images_bucket" {
  name  = "/uni-prop/${var.stage}/ImagesBucket"
  type  = "String"
  value = aws_s3_bucket.unicorn_properties_images.bucket
  tags  = local.common_tags
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

  tags = local.common_tags
}

resource "aws_iam_role_policy" "image_upload_lambda_policy" {
  name = "uni-prop-${var.stage}-image-upload-lambda-policy"
  role = aws_iam_role.image_upload_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.unicorn_properties_images.arn,
          "${aws_s3_bucket.unicorn_properties_images.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:DeleteBucket"
        ]
        Resource = aws_s3_bucket.unicorn_properties_images.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:*"
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

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "image_upload_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.image_upload.function_name}"
  retention_in_days = var.stage == "prod" ? 14 : 3
  tags              = local.common_tags
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








