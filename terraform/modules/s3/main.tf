# Bronze / Silver / Gold / Scripts buckets — names match the convention
# already baked into iam_permission/*.json and the Step Functions ASL
# (yt-pipeline-<layer>-<region>-<account_id>), just pointed at the real account.

locals {
  buckets = {
    bronze  = "yt-pipeline-bronze-${var.region}-${var.account_id}"
    silver  = "yt-pipeline-silver-${var.region}-${var.account_id}"
    gold    = "yt-pipeline-gold-${var.region}-${var.account_id}"
    scripts = "yt-pipeline-scripts-${var.region}-${var.account_id}"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets
  bucket   = each.value
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
