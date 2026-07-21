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
    # Athena's ATHENA_STAGING_DIR (this pod's profiles.yml s3_staging_dir)
    # points at the raw bucket's athena-results/ prefix — every query dbt
    # runs writes its own result/metadata file there regardless of whether
    # the query's actual DATA target is curated/enriched, so this needs
    # write access even though dbt otherwise only reads from raw.
    # Confirmed against a real dbt build: it got all the way through
    # `dbt build` (5 models, 16 tests) and only failed writing this file.
    sid       = "RawAthenaResultsWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.raw_bucket_arn}/athena-results/*"]
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
    # dbt-athena's list_schemas() calls the catalog-wide GetDatabases (plural)
    # API, distinct from the per-database GetDatabase (singular) granted
    # above — GetDatabases has no per-database resource scoping, it always
    # lists every database in the catalog, so this can only be granted at
    # the catalog level. Confirmed against a real dbt build failure
    # (AccessDeniedException on glue:GetDatabases) — every dbt invocation
    # calls this early, before touching any specific table.
    sid       = "GlueListDatabases"
    effect    = "Allow"
    actions   = ["glue:GetDatabases"]
    resources = ["arn:aws:glue:${var.region}:${var.account_id}:catalog"]
  }

  statement {
    # dbt-athena's contract/schema-drift checks call GetTableVersions —
    # confirmed against a real dbt build (AccessDeniedException on
    # glue:GetTableVersions, resource: the catalog) after every other model
    # and 20/21 tests had already passed. Granted at both catalog and the
    # specific table-scoped ARNs (the CreateDatabase lesson: some Glue
    # catalog APIs get evaluated against either scope depending on the
    # call shape, so cover both rather than risk a second round-trip).
    sid     = "GlueTableVersions"
    effect  = "Allow"
    actions = ["glue:GetTableVersions"]
    resources = [
      "arn:aws:glue:${var.region}:${var.account_id}:catalog",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.raw_database_name}/*",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.curated_database_name}/*",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.enriched_database_name}/*",
    ]
  }

  statement {
    # dbt-athena runs CREATE SCHEMA IF NOT EXISTS for every target schema on
    # each invocation, unconditionally — even though curated_db/enriched_db
    # already exist and this is a no-op every time. Unlike GetDatabases,
    # AWS evaluates glue:CreateDatabase against the ARN of the database
    # NAME being created (not just the catalog) — confirmed by the actual
    # AccessDeniedException message naming
    # "resource: .../database/yt_pipeline_enriched_db" specifically, after
    # a first attempt scoped to only the catalog ARN still failed. Needs
    # both: the catalog (the API call itself operates at that level) and
    # each specific target database name.
    sid     = "GlueCreateDatabase"
    effect  = "Allow"
    actions = ["glue:CreateDatabase"]
    resources = [
      "arn:aws:glue:${var.region}:${var.account_id}:catalog",
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.curated_database_name}",
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.enriched_database_name}",
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
