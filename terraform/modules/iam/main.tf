# Reuses the exact permission statements from iam_permission/*.json (via the
# account/region-parameterized copies in terraform/templates/) — only the
# account ID substitution is new, the permission logic itself is untouched.
#
# The Lambda execution role used to live here as one shared role for all
# Lambdas. It's now split into terraform/modules/iam-ingest, iam-transform,
# iam-dbt-trigger, and iam-dbt-runtime — each scoped to exactly what that one
# Lambda/pod needs.
#
# The Glue job role that used to live here is retired along with the Glue
# Spark jobs themselves (glue_jobs/) — there's no more PySpark ETL for a Glue
# job role to run under. Every remaining transformation runs either as a
# Lambda (raw-transform) or dbt against Athena (curated/enriched), each with
# its own role.

# ── Step Functions execution role ───────────────────────────────────────────

data "aws_iam_policy_document" "sfn_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "yt-data-pipeline-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_trust.json
}

resource "aws_iam_role_policy" "sfn" {
  name = "yt-data-pipeline-sfn-access"
  role = aws_iam_role.sfn.id
  policy = templatefile("${var.templates_path}/sfn-access.json.tftpl", {
    region     = var.region
    account_id = var.account_id
  })
}

# ── EventBridge → Step Functions execution role ─────────────────────────────

data "aws_iam_policy_document" "eventbridge_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge" {
  name               = "yt-data-pipeline-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_trust.json
}

data "aws_iam_policy_document" "eventbridge_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = ["arn:aws:states:${var.region}:${var.account_id}:stateMachine:yt-data-pipeline"]
  }
}

resource "aws_iam_role_policy" "eventbridge" {
  name   = "yt-data-pipeline-eventbridge-access"
  role   = aws_iam_role.eventbridge.id
  policy = data.aws_iam_policy_document.eventbridge_permissions.json
}
