# Dedicated logging bucket + a single multi-region trail. Management events
# only by default — matches this repo's existing cost-consciousness (no NAT
# gateway anywhere, isolated per-consumer Athena workgroups). S3 data events
# on the raw/curated/enriched buckets are meaningfully more expensive at
# pipeline scale (billed per-event, and this pipeline runs hourly) — left as
# a commented opt-in below rather than on by default.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "yt-pipeline-cloudtrail-logs-${var.region}-${var.account_id}"
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Log-only bucket, unlike the data buckets — old CloudTrail logs have no
# analytical value once past a retention window, so expire them rather than
# let them accumulate forever.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    id     = "expire-old-trail-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 365
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${var.account_id}:trail/yt-pipeline-trail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${var.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${var.account_id}:trail/yt-pipeline-trail"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}

resource "aws_cloudtrail" "this" {
  name                          = "yt-pipeline-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # No data_resource blocks here on purpose — management events only.
    # To add S3 data-event auditing on the pipeline's own buckets later
    # (higher cost, billed per object-level API call), add e.g.:
    #
    # event_selector {
    #   read_write_type           = "All"
    #   include_management_events = false
    #   data_resource {
    #     type   = "AWS::S3::Object"
    #     values = ["${var.raw_bucket_arn}/", "${var.curated_bucket_arn}/", "${var.enriched_bucket_arn}/"]
    #   }
    # }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}
