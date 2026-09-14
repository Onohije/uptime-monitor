variable "alert_email" {
  description = "Address that receives up/down alerts"
  type        = string
  default     = "igbadumeonoh@gmail.com"
}

resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:Messages contain only target URLs and status codes. SSE-KMS would require kms:GenerateDataKey through the Lambda permissions boundary, adding a failure path to the alerting itself
  name = "uptime-monitor-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
