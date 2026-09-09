variable "github_repo" {
  description = "GitHub repo allowed to assume the deploy role, as owner/name"
  type        = string
  default     = "Onohije/uptime-monitor"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
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
            "repo:${var.github_repo}:ref:refs/heads/main",
            "repo:${var.github_repo}:pull_request"
          ]
        }
      }
    }]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
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
        Resource = "${aws_s3_bucket.tf_state.arn}/uptime-monitor/*"
      }
    ]
  })
}
