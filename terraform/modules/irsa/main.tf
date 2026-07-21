# IRSA (IAM Roles for Service Accounts) role for the dashboard pod — read-only,
# deliberately separate from and narrower than the Lambda execution role.

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

resource "aws_iam_role" "dashboard" {
  name               = "yt-pipeline-dashboard-irsa"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "dashboard_readonly" {
  statement {
    sid    = "StepFunctionsTriggerAndRead"
    effect = "Allow"
    actions = [
      "states:ListExecutions",
      "states:DescribeExecution",
      "states:GetExecutionHistory",
      "states:DescribeStateMachine",
      "states:StartExecution",
    ]
    resources = [
      var.state_machine_arn,
      "arn:aws:states:${var.region}:${var.account_id}:execution:yt-data-pipeline:*",
    ]
  }

  statement {
    sid    = "AthenaReadOnly"
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
    sid    = "GlueReadOnly"
    effect = "Allow"
    actions = [
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetDatabase",
      "glue:GetPartitions",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${var.account_id}:catalog",
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.enriched_glue_db_name}",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.enriched_glue_db_name}/*",
    ]
  }

  statement {
    sid    = "EnrichedAndAthenaResultsReadOnly"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      var.enriched_bucket_arn,
      "${var.enriched_bucket_arn}/*",
    ]
  }

  statement {
    # Athena writes query results to S3 using the CALLING principal's
    # credentials, not a separate service role — without these, every
    # athena:StartQueryExecution call (even a read-only SELECT) fails with
    # S3 AccessDenied when Athena tries to write results to the workgroup's
    # output location. This was missing even for the existing read-only
    # Gold-stats queries.
    sid    = "AthenaResultsWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetBucketLocation",
    ]
    resources = [
      var.enriched_bucket_arn,
      "${var.enriched_bucket_arn}/athena-dashboard-results/*",
    ]
  }

  statement {
    # yt_pipeline_enriched_db is Lake Formation-governed with full enforcement
    # (see terraform/modules/lakeformation) — the Glue/S3 grants above are
    # necessary but not sufficient on their own; without this, Athena calls
    # fail with an opaque AccessDeniedException. The actual table-level grant
    # for this role lives in the lakeformation module, not here.
    sid       = "LakeFormationDataAccess"
    effect    = "Allow"
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "dashboard_readonly" {
  name   = "yt-pipeline-dashboard-readonly"
  role   = aws_iam_role.dashboard.id
  policy = data.aws_iam_policy_document.dashboard_readonly.json
}
