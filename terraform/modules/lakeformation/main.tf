# Lake Formation admin registration MUST come first, explicitly, every time
# this module is touched — this is the exact same trap as the EKS
# bootstrap_cluster_creator_admin_permissions bug fixed earlier in this repo's
# history (see terraform/modules/eks/main.tf): whichever IAM principal
# happens to run `terraform apply` first becomes an implicit admin unless
# `admins` names one explicitly. If a human applies this locally once instead
# of CI, gha-deploy-role gets zero LF admin standing, and every future
# CI-driven apply/query against these databases fails with a permissions
# error that looks unrelated to Lake Formation. Every other resource below
# depends_on this one to guarantee ordering.
resource "aws_lakeformation_data_lake_settings" "this" {
  admins = var.admin_principal_arns

  # Turns off the account-wide "auto-grant IAMAllowedPrincipals to every new
  # database/table" behavior that's otherwise the default — this is the
  # actual account-wide control point for LF enforcement (there is no
  # per-database toggle for the *default* behavior). Enforcement is then
  # restored per-database below: curated/enriched get nothing back (governed
  # solely by the explicit principal grants further down), while raw gets an
  # explicit, deliberate IAM_ALLOWED_PRINCIPALS grant so it stays on the
  # simpler IAM-only model.
  create_database_default_permissions {
    permissions = []
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }
  create_table_default_permissions {
    permissions = []
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }
}

# A custom data-access role instead of use_service_linked_role=true: the
# service-linked role (AWSServiceRoleForLakeFormationDataAccess) failed to
# read S3 objects in a real query against enriched — confirmed via
# PERMISSION_DENIED s3:GetObject errors from that exact role during a dbt
# build, on Iceberg metadata files it should have had automatic access to.
# An explicit role LF assumes itself (the documented "register a custom
# role for a data lake location" pattern) is more reliable and fully
# within this project's own IAM control rather than depending on an
# AWS-managed role's policy propagation.
data "aws_iam_policy_document" "lf_data_access_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lakeformation.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lf_data_access" {
  name               = "yt-pipeline-lakeformation-data-access"
  assume_role_policy = data.aws_iam_policy_document.lf_data_access_trust.json
}

data "aws_iam_policy_document" "lf_data_access_permissions" {
  statement {
    sid    = "DataLakeLocationsReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      var.raw_bucket_arn, "${var.raw_bucket_arn}/*",
      var.curated_bucket_arn, "${var.curated_bucket_arn}/*",
      var.enriched_bucket_arn, "${var.enriched_bucket_arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "lf_data_access" {
  name   = "yt-pipeline-lakeformation-data-access"
  role   = aws_iam_role.lf_data_access.id
  policy = data.aws_iam_policy_document.lf_data_access_permissions.json
}

# Only raw/curated/enriched are registered — staging is plain JSON, never
# Glue-cataloged, so there's nothing for Lake Formation to govern there.
resource "aws_lakeformation_resource" "raw" {
  arn        = var.raw_bucket_arn
  role_arn   = aws_iam_role.lf_data_access.arn
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_resource" "curated" {
  arn        = var.curated_bucket_arn
  role_arn   = aws_iam_role.lf_data_access.arn
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_resource" "enriched" {
  arn        = var.enriched_bucket_arn
  role_arn   = aws_iam_role.lf_data_access.arn
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

# ── Raw: the raw-transform Lambda writes here ───────────────────────────────
#
# Lake Formation's grantable permission set differs by resource type: a
# `database {}` grant only accepts CREATE_TABLE/ALTER/DROP/DESCRIBE — SELECT
# and INSERT are table-level-only permissions and mixing them into one grant
# targeting a database fails with a generic "Permissions modification is
# invalid" (confirmed against real AWS during this project's first apply).
# So every principal below gets two grants: one on the database (schema-level
# DDL) and one on `table { wildcard = true }` within that database (row-level
# DML on every table in it, present and future) — not one combined grant.

resource "aws_lakeformation_permissions" "raw_transform_db" {
  principal   = var.raw_transform_role_arn
  permissions = ["CREATE_TABLE", "ALTER", "DESCRIBE"]
  database {
    name = var.raw_database_name
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "raw_transform_tables" {
  principal   = var.raw_transform_role_arn
  permissions = ["SELECT", "INSERT", "DESCRIBE"]
  table {
    database_name = var.raw_database_name
    wildcard      = true
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "raw_transform_location" {
  principal   = var.raw_transform_role_arn
  permissions = ["DATA_LOCATION_ACCESS"]
  data_location {
    arn = var.raw_bucket_arn
  }
  depends_on = [aws_lakeformation_resource.raw]
}

# ── dbt: reads raw, writes curated + enriched ───────────────────────────────

resource "aws_lakeformation_permissions" "dbt_raw_read" {
  principal   = var.dbt_role_arn
  permissions = ["DESCRIBE"]
  database {
    name = var.raw_database_name
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "dbt_raw_tables_read" {
  principal   = var.dbt_role_arn
  permissions = ["SELECT", "DESCRIBE"]
  table {
    database_name = var.raw_database_name
    wildcard      = true
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "dbt_curated_db" {
  principal   = var.dbt_role_arn
  permissions = ["CREATE_TABLE", "ALTER", "DROP", "DESCRIBE"]
  database {
    name = var.curated_database_name
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "dbt_curated_tables" {
  principal   = var.dbt_role_arn
  permissions = ["SELECT", "INSERT", "DESCRIBE"]
  table {
    database_name = var.curated_database_name
    wildcard      = true
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "dbt_curated_location" {
  principal   = var.dbt_role_arn
  permissions = ["DATA_LOCATION_ACCESS"]
  data_location {
    arn = var.curated_bucket_arn
  }
  depends_on = [aws_lakeformation_resource.curated]
}

resource "aws_lakeformation_permissions" "dbt_enriched_db" {
  principal   = var.dbt_role_arn
  permissions = ["CREATE_TABLE", "ALTER", "DROP", "DESCRIBE"]
  database {
    name = var.enriched_database_name
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "dbt_enriched_tables" {
  principal   = var.dbt_role_arn
  permissions = ["SELECT", "INSERT", "DESCRIBE"]
  table {
    database_name = var.enriched_database_name
    wildcard      = true
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "dbt_enriched_location" {
  principal   = var.dbt_role_arn
  permissions = ["DATA_LOCATION_ACCESS"]
  data_location {
    arn = var.enriched_bucket_arn
  }
  depends_on = [aws_lakeformation_resource.enriched]
}

# ── Dashboard (EKS/IRSA): reads enriched only ───────────────────────────────

resource "aws_lakeformation_permissions" "dashboard_enriched_read" {
  principal   = var.dashboard_role_arn
  permissions = ["DESCRIBE"]
  database {
    name = var.enriched_database_name
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "dashboard_enriched_tables_read" {
  principal   = var.dashboard_role_arn
  permissions = ["SELECT", "DESCRIBE"]
  table {
    database_name = var.enriched_database_name
    wildcard      = true
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

# ── QuickSight: reads enriched only ─────────────────────────────────────────

resource "aws_lakeformation_permissions" "quicksight_enriched_read" {
  count       = var.quicksight_role_arn != null ? 1 : 0
  principal   = var.quicksight_role_arn
  permissions = ["DESCRIBE"]
  database {
    name = var.enriched_database_name
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

resource "aws_lakeformation_permissions" "quicksight_enriched_tables_read" {
  count       = var.quicksight_role_arn != null ? 1 : 0
  principal   = var.quicksight_role_arn
  permissions = ["SELECT", "DESCRIBE"]
  table {
    database_name = var.enriched_database_name
    wildcard      = true
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}

# ── Raw stays on the permissive IAM-fallback model, deliberately ───────────
# curated/enriched get NO equivalent grant, which — combined with the
# account-wide defaults being turned off above — means they're governed
# exclusively by the explicit principal grants above (dbt, QuickSight) plus
# the admins list. That's what "full enforcement" actually means here: not a
# revocation, but the absence of ever granting the fallback in the first
# place. Sequenced after the admin settings via depends_on — LF admins bypass
# permission checks entirely, so that grant is the safety net if anything
# above is ever wrong; do not reorder this ahead of the admin settings.
resource "aws_lakeformation_permissions" "raw_iam_fallback" {
  principal   = "IAM_ALLOWED_PRINCIPALS"
  permissions = ["ALL"]
  database {
    name = var.raw_database_name
  }
  depends_on = [aws_lakeformation_data_lake_settings.this]
}
