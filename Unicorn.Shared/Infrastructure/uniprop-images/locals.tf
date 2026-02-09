locals {
  bucket_name = "uni-prop-${var.stage}-images-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.id}"
  common_tags = {
    stage   = var.stage
    project = "AWS Serverless Developer Experience"
    service = "Unicorn Base Infrastructure"
  }
}
