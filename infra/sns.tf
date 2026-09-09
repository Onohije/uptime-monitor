variable "alert_email" {
  description = "Address that receives up/down alerts"
  type        = string
  default     = "igbadumeonoh@gmail.com"
}

resource "aws_sns_topic" "alerts" {
  name = "uptime-monitor-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
