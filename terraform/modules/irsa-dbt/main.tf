# IRSA role for the dbt pod (a Kubernetes Job the trigger Lambda creates in
# the "data-pipeline" namespace) — same mechanism as terraform/modules/irsa
# (the dashboard's role), deliberately a separate role/module since this pod
# needs read on raw + create/write on curated/enriched, nothing the dashboard
# role should ever have.

locals {
  oidc_issuer_host = replace(var.oidc_provider_url, "https://", "")
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dbt" {
  name               = "yt-pipeline-dbt-irsa"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "dbt" {
  statement {
    # s3:GetBucketLocation is a distinct, separate requirement from
    # ListBucket/GetObject — Athena's StartQueryExecution calls it to
    # verify the query's output/staging bucket before running anything, and
    # fails with "Unable to verify/create output bucket" without it
    # (confirmed on the raw-transform Lambda's identical gap against a real
    # execution — every dbt query goes through Athena the same way).
    sid    = "RawRead"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [var.raw_bucket_arn, "${var.raw_bucket_arn}/*"]
  }

  statement {
    sid    = "CuratedEnrichedReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      var.curated_bucket_arn, "${var.curated_bucket_arn}/*",
      var.enriched_bucket_arn, "${var.enriched_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "GlueRawRead"
    effect = "Allow"
    actions = [
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetDatabase",
      "glue:GetPartitions",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${var.account_id}:catalog",
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.raw_database_name}",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.raw_database_name}/*",
    ]
  }

  statement {
    sid    = "GlueCuratedEnrichedReadWrite"
    effect = "Allow"
    actions = [
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetDatabase",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:GetPartitions",
      "glue:CreatePartition",
      "glue:BatchCreatePartition",
      "glue:DeletePartition",
      "glue:BatchDeletePartition",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${var.account_id}:catalog",
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.curated_database_name}",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.curated_database_name}/*",
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.enriched_database_name}",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.enriched_database_name}/*",
    ]
  }

  statement {
    sid    = "AthenaQuery"
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
      "athena:GetWorkGroup",
    ]
    resources = ["arn:aws:athena:${var.region}:${var.account_id}:workgroup/${var.athena_workgroup_name}"]
  }

  statement {
    # Same gotcha as the raw-transform Lambda (see iam-transform) — Athena
    # calls against LF-registered databases fail without this, regardless of
    # how permissive the Glue/S3 grants above look.
    sid       = "LakeFormationDataAccess"
    effect    = "Allow"
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "dbt" {
  name   = "yt-pipeline-dbt-access"
  role   = aws_iam_role.dbt.id
  policy = data.aws_iam_policy_document.dbt.json
}
