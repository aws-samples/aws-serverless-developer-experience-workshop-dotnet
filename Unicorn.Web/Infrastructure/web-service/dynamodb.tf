resource "aws_dynamodb_table" "properties_table" {
  name         = "PropertiesTable-${var.stage}"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "PK"
  range_key = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  tags = local.common_tags
}








