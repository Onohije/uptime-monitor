locals {
  function_name = "uptime-monitor-checker"
  boundary_arn  = "arn:aws:iam::533267195508:policy/uptime-monitor-lambda-boundary"
}

# Zips the source at plan time. output_base64sha256 changes whenever the code
# changes, which is what makes Terraform redeploy the function.
data "archive_file" "checker" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/checker.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "checker" {
  name                 = "${local.function_name}-role"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role.json
  permissions_boundary = local.boundary_arn
}

resource "aws_iam_role_policy" "checker" {
  name = "checker-runtime"
  role = aws_iam_role.checker.id

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
        Resource = "${aws_cloudwatch_log_group.checker.arn}:*"
      },
      {
        Sid      = "WriteChecks"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.checks.arn
      },
      {
        Sid      = "PublishAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "checker" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "checker" {
  function_name = local.function_name
  role          = aws_iam_role.checker.arn

  filename         = data.archive_file.checker.output_path
  source_code_hash = data.archive_file.checker.output_base64sha256

  runtime     = "python3.13"
  handler     = "checker.handler"
  timeout     = 60
  memory_size = 256

  environment {
    variables = {
      TABLE_NAME      = aws_dynamodb_table.checks.name
      TARGETS         = join(",", var.targets)
      TIMEOUT_SECONDS = "10"
      RETENTION_DAYS  = "30"
      TOPIC_ARN       = aws_sns_topic.alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.checker]
}
