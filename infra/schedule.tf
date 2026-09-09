resource "aws_cloudwatch_event_rule" "checker" {
  name                = "uptime-monitor-every-5-minutes"
  description         = "Triggers the uptime checker on a fixed cadence"
  schedule_expression = "rate(5 minutes)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "checker" {
  rule      = aws_cloudwatch_event_rule.checker.name
  target_id = "checker-lambda"
  arn       = aws_lambda_function.checker.arn
}

# EventBridge is a separate service, so invoking the function needs an explicit
# resource-based policy on the function itself. The role on the Lambda governs
# what the function can do; this governs who may call it.
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.checker.arn
}
