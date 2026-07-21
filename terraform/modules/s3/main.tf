# Staging / Raw / Curated / Enriched buckets — names match the convention
# already baked into the Step Functions ASL and dbt profile env vars
# (yt-pipeline-<layer>-<region>-<account_id>), just pointed at the real account.
# No "scripts" bucket anymore — that only existed to stage the PySpark ETL
# scripts, which are gone (replaced by the raw-transform Lambda + dbt models).

locals {
  buckets = {
    staging  = "yt-pipeline-staging-${var.region}-${var.account_id}"
    raw      = "yt-pipeline-raw-${var.region}-${var.account_id}"
    curated  = "yt-pipeline-curated-${var.region}-${var.account_id}"
    enriched = "yt-pipeline-enriched-${var.region}-${var.account_id}"
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
