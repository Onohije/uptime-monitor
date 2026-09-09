variable "github_repo" {
  description = "GitHub repo allowed to assume the deploy role, as owner/name"
  type        = string
  default     = "Onohije/uptime-monitor"
}

variable "github_repo_with_ids" {
  description = "Same repo in GitHub's owner@ownerid/repo@repoid subject form"
  type        = string
  default     = "Onohije@116710916/uptime-monitor@1362662025"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_actions" {
  name        = "uptime-monitor-github-actions"
  description = "Assumed by GitHub Actions via OIDC to deploy uptime-monitor"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repo_with_ids}:ref:refs/heads/main",
            "repo:${var.github_repo_with_ids}:pull_request",
            "repo:${var.github_repo}:ref:refs/heads/main",
            "repo:${var.github_repo}:pull_request"
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "terraform_state" {
  name = "terraform-state-access"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.tf_state.arn
      },
      {
        Sid    = "ReadWriteStateFile"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.tf_state.arn}/uptime-monitor/infra.tfstate*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

resource "aws_iam_role_policy" "dynamodb" {
  name = "dynamodb-checks-table"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ManageChecksTable"
      Effect = "Allow"
      Action = [
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:DescribeTable",
        "dynamodb:DescribeContinuousBackups",
        "dynamodb:DescribeTimeToLive",
        "dynamodb:UpdateTable",
        "dynamodb:UpdateTimeToLive",
        "dynamodb:TagResource",
        "dynamodb:UntagResource",
        "dynamodb:ListTagsOfResource"
      ]
      Resource = "arn:aws:dynamodb:eu-west-2:533267195508:table/uptime-monitor-*"
    }]
  })
}

# The ceiling: any role the pipeline creates is capped by this, whatever
# policy gets attached to it. Effective permissions = policy AND boundary.
resource "aws_iam_policy" "lambda_boundary" {
  name        = "uptime-monitor-lambda-boundary"
  description = "Maximum permissions any uptime-monitor Lambda role may have"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:eu-west-2:533267195508:log-group:/aws/lambda/uptime-monitor-*:*"
      },
      {
        Sid    = "ChecksTableData"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = "arn:aws:dynamodb:eu-west-2:533267195508:table/uptime-monitor-*"
      },
      {
        Sid      = "Alerting"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "arn:aws:sns:eu-west-2:533267195508:uptime-monitor-*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_infra" {
  name = "lambda-and-supporting-resources"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateBoundedRolesOnly"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:PutRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:DeleteRolePolicy"
        ]
        Resource = "arn:aws:iam::533267195508:role/uptime-monitor-*"
        Condition = {
          StringEquals = {
            "iam:PermissionsBoundary" = aws_iam_policy.lambda_boundary.arn
          }
        }
      },
      {
        Sid    = "ReadAndDeleteOwnRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:DeleteRole",
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::533267195508:role/uptime-monitor-*"
      },
      {
        Sid    = "NeverEscapeTheBoundary"
        Effect = "Deny"
        Action = [
          "iam:DeleteRolePermissionsBoundary",
          "iam:PutRolePermissionsBoundary"
        ]
        Resource = "*"
      },
      {
        Sid    = "ManageFunctions"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:ListVersionsByFunction",
          "lambda:PublishVersion",
          "lambda:GetFunctionCodeSigningConfig",
          "lambda:GetFunctionEventInvokeConfig",
          "lambda:PutFunctionEventInvokeConfig",
          "lambda:GetFunctionConcurrency",
          "lambda:PutFunctionConcurrency",
          "lambda:InvokeFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:DeleteFunction",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:ListTags"
        ]
        Resource = "arn:aws:lambda:eu-west-2:533267195508:function:uptime-monitor-*"
      },
      {
        Sid    = "ManageLogGroups"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:ListTagsForResource"
        ]
        Resource = "arn:aws:logs:eu-west-2:533267195508:log-group:/aws/lambda/uptime-monitor-*"
      },
      {
        Sid      = "DescribeLogGroups"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge" {
  name = "eventbridge-schedule"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ManageScheduleRules"
      Effect = "Allow"
      Action = [
        "events:PutRule",
        "events:DeleteRule",
        "events:DescribeRule",
        "events:EnableRule",
        "events:DisableRule",
        "events:PutTargets",
        "events:RemoveTargets",
        "events:ListTargetsByRule",
        "events:ListTagsForResource",
        "events:TagResource",
        "events:UntagResource"
      ]
      Resource = "arn:aws:events:eu-west-2:533267195508:rule/uptime-monitor-*"
    }]
  })
}
