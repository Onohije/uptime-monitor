# Terraform manages the page itself, so a change to index.html deploys like any
# other change - reviewed on the PR, applied on merge.
resource "aws_s3_object" "index" {
  bucket = aws_s3_bucket.site.id
  key    = "index.html"

  source = "${path.module}/site/index.html"
  etag   = filemd5("${path.module}/site/index.html")

  content_type  = "text/html; charset=utf-8"
  cache_control = "public, max-age=60"
}