data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "yt-pipeline-lambda-raw-transform-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# Writing Iceberg tables via awswrangler.athena.to_iceberg() drives Athena as
# the write engine (CTAS/INSERT under the hood) rather than Spark — so this
# role needs Athena query permissions in addition to the S3/Glue permissions
# a plain-Parquet writer would need. Table access for that Athena query is
# additionally gated by Lake Formation once yt_pipeline_raw_db is registered
# (see terraform/modules/lakeformation) — lakeformation:GetDataAccess is
# required on top of the Glue grants below, or Athena calls fail with an
# opaque AccessDeniedException that looks like an IAM problem but isn't.
data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "StagingRead"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.staging_bucket_arn, "${var.staging_bucket_arn}/*"]
  }

  statement {
    sid       = "RawReadWrite"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [var.raw_bucket_arn, "${var.raw_bucket_arn}/*"]
  }

  statement {
    sid    = "GlueCatalogReadWrite"
    effect = "Allow"
    actions = [
      "glue:GetTable",
      "glue:GetDatabase",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:GetPartitions",
      "glue:CreatePartition",
      "glue:BatchCreatePartition",
      "glue:DeletePartition",
      "glue:BatchDeletePartition",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${var.account_id}:catalog",
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.glue_raw_db}",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.glue_raw_db}/*",
    ]
  }

  statement {
    sid    = "AthenaIcebergWrite"
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:GetWorkGroup",
    ]
    resources = ["arn:aws:athena:${var.region}:${var.account_id}:workgroup/${var.athena_workgroup_name}"]
  }

  statement {
    sid       = "LakeFormationDataAccess"
    effect    = "Allow"
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }

  statement {
    sid       = "SNSAccess"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "yt-pipeline-lambda-raw-transform-access"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

resource "aws_iam_role_policy_attachment" "basic_exec" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
