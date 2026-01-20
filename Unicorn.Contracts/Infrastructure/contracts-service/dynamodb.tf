resource "aws_dynamodb_table" "contracts_table" {
  name         = "ContractsTable-${var.stage}"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "PropertyId"

  attribute {
    name = "PropertyId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = local.common_tags
}








