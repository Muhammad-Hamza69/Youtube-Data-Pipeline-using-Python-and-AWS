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
    sid    = "StepFunctionsReadOnly"
    effect = "Allow"
    actions = [
      "states:ListExecutions",
      "states:DescribeExecution",
      "states:GetExecutionHistory",
      "states:DescribeStateMachine",
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
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.silver_glue_db_name}",
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.gold_glue_db_name}",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.silver_glue_db_name}/*",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.gold_glue_db_name}/*",
    ]
  }

  statement {
    sid    = "GoldAndAthenaResultsReadOnly"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      var.gold_bucket_arn,
      "${var.gold_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "dashboard_readonly" {
  name   = "yt-pipeline-dashboard-readonly"
  role   = aws_iam_role.dashboard.id
  policy = data.aws_iam_policy_document.dashboard_readonly.json
}
