data "aws_caller_identity" "current" {}

locals {
  site_bucket = "uptime-monitor-status-${data.aws_caller_identity.current.account_id}"
}

# The bucket is private. Only CloudFront may read it.
resource "aws_s3_bucket" "site" {
  #checkov:skip=CKV_AWS_18:Access logging needs a second bucket and ongoing storage cost. The content is a public status page; there are no sensitive access patterns to audit
  #checkov:skip=CKV_AWS_144:Content is regenerated from DynamoDB every few minutes. Cross-region replication would double storage cost to protect nothing irreplaceable
  #checkov:skip=CKV_AWS_145:Public content. AES256 with the AWS-managed key is sufficient; a CMK adds cost with no confidentiality gain
  #checkov:skip=CKV2_AWS_62:No consumer exists for object events. An unused notification configuration is dead config
  bucket = local.site_bucket
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Versioning without expiry grows without bound. The page is regenerated every
# few minutes, so 30 days of history is generous.
resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Origin Access Control: CloudFront signs its requests to S3 with SigV4, so the
# bucket can stay private. Replaces the older Origin Access Identity.
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "uptime-monitor-status"
  description                       = "Signs CloudFront requests to the status bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  #checkov:skip=CKV_AWS_68:WAF costs ~GBP 4/month plus per-rule charges. The origin is a static JSON file with no application logic, no auth and no write path
  #checkov:skip=CKV2_AWS_47:Same as above - no WAF, so no Log4j managed rule. Nothing here parses user input
  #checkov:skip=CKV_AWS_86:Access logging needs a second bucket and storage cost for traffic nobody analyses
  #checkov:skip=CKV_AWS_310:Single S3 origin, already replicated across availability zones. A second origin would have nothing different to serve
  #checkov:skip=CKV_AWS_374:A public status page should be reachable from anywhere. Geo restriction would be actively wrong here
  #checkov:skip=CKV_AWS_174:The free *.cloudfront.net certificate does not allow setting a minimum TLS version. Fixing this requires a custom domain and an ACM certificate
  #checkov:skip=CKV2_AWS_32:A response headers policy IS attached - the AWS managed SecurityHeadersPolicy, by ID. Checkov only recognises a reference to a policy resource, so it cannot see it
  #checkov:skip=CKV2_AWS_42:Requires a custom domain. Using the default CloudFront certificate until one exists

  enabled             = true
  default_root_object = "index.html"
  comment             = "uptime-monitor status page"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "status-bucket"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "status-bucket"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # CachingOptimized, an AWS managed policy.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    # SecurityHeadersPolicy, an AWS managed policy: HSTS, X-Content-Type-Options,
    # X-Frame-Options, Referrer-Policy. Free, and applies at the edge.
    response_headers_policy_id = "67f7725c-6f97-4210-82d7-5512b31e9d03"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Grants exactly one distribution read access, and nothing else.
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontRead"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.site.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
        }
      }
    }]
  })
}

output "status_page_url" {
  value = "https://${aws_cloudfront_distribution.site.domain_name}"
}