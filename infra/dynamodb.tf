resource "aws_dynamodb_table" "checks" {
  name         = "uptime-monitor-checks"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "target"
  range_key = "checked_at"

  attribute {
    name = "target"
    type = "S"
  }

  attribute {
    name = "checked_at"
    type = "N"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}
