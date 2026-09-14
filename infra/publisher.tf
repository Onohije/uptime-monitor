locals {
  publisher_name = "uptime-monitor-publisher"
}

data "archive_file" "publisher" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-publisher"
  output_path = "${path.module}/build/publisher.zip"
  excludes    = ["__pycache__"]
}

resource "aws_iam_role" "publisher" {
  name                 = "${local.publisher_name}-role"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role.json
  permissions_boundary = local.boundary_arn
}

resource "aws_iam_role_policy" "publisher" {
  name = "publisher-runtime"
  role = aws_iam_role.publisher.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.publisher.arn}:*"
      },
      {
        Sid      = "ReadChecks"
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = aws_dynamodb_table.checks.arn
      },
      {
        Sid      = "PublishStatus"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.site.arn}/status.json"
      },
      {
        Sid      = "DeadLetter"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "publisher" {
  #checkov:skip=CKV_AWS_158:Encrypted with the AWS-managed key. Logs hold no secrets; a CMK adds cost without benefit
  #checkov:skip=CKV_AWS_338:14 days is deliberate. These are operational logs; the durable record lives in DynamoDB
  name              = "/aws/lambda/${local.publisher_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "publisher" {
  #checkov:skip=CKV_AWS_173:Environment variables hold a table name, a bucket name and public URLs. Already encrypted with the AWS-managed key
  #checkov:skip=CKV_AWS_272:Code signing requires AWS Signer. Source is a single file from this repo, deployed only through a reviewed pipeline
  #checkov:skip=CKV_AWS_50:One function with no downstream calls to trace. Enabling X-Ray would also require widening the permissions boundary
  #checkov:skip=CKV_AWS_117:No VPC. The function talks only to AWS APIs; a VPC would add endpoints or a NAT gateway for no gain
  #checkov:skip=CKV_AWS_115:This account's total concurrency limit is 10, and AWS requires at least 10 unreserved

  function_name = local.publisher_name
  role          = aws_iam_role.publisher.arn

  filename         = data.archive_file.publisher.output_path
  source_code_hash = data.archive_file.publisher.output_base64sha256

  runtime     = "python3.13"
  handler     = "publisher.handler"
  timeout     = 30
  memory_size = 256

  dead_letter_config {
    target_arn = aws_sns_topic.alerts.arn
  }

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.checks.name
      BUCKET       = aws_s3_bucket.site.id
      TARGETS      = join(",", var.targets)
      WINDOW_HOURS = "24"
      SAMPLE_LIMIT = "60"
    }
  }

  depends_on = [aws_cloudwatch_log_group.publisher]
}

# Runs two minutes after the checker, so the newest result is always included.
resource "aws_cloudwatch_event_rule" "publisher" {
  name                = "uptime-monitor-publish-every-5-minutes"
  description         = "Regenerates the public status summary"
  schedule_expression = "rate(5 minutes)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "publisher" {
  rule      = aws_cloudwatch_event_rule.publisher.name
  target_id = "publisher-lambda"
  arn       = aws_lambda_function.publisher.arn
}

resource "aws_lambda_permission" "allow_eventbridge_publisher" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.publisher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.publisher.arn
}