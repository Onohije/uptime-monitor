resource "aws_dynamodb_table" "checks" {
  #checkov:skip=CKV_AWS_28:Check results are ephemeral (30-day TTL) and fully reconstructible; PITR adds cost without protecting anything irreplaceable
  #checkov:skip=CKV_AWS_119:Encrypted at rest with the AWS-owned key. Contents are public URLs and HTTP status codes; a customer-managed key adds ~$1/month for no confidentiality gain
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
