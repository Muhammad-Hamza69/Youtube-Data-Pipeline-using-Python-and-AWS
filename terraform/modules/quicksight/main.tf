# QuickSight subscription now exists on this account (Enterprise edition,
# confirmed via `aws quicksight describe-account-subscription`). This module
# wires up the Athena data source + one SPICE dataset per Enriched table,
# refreshed daily, plus the IAM permissions QuickSight's own auto-created
# service role needs to actually read Enriched through Lake Formation. It
# deliberately does NOT hand-author the aws_quicksight_dashboard/analysis
# `definition` here — that JSON is built and applied via the AWS CLI
# (scripts/quicksight_dashboard.json / a one-time `aws quicksight
# create-dashboard` call) since it's genuinely large visual layout content,
# not infrastructure wiring, and iterates far faster outside Terraform's
# HCL translation of the same JSON. This mirrors the same "manual/scripted
# for the one thing that's really content, not infra" line already drawn for
# k8s/argocd/application.yaml.

data "aws_caller_identity" "current" {}

# QuickSight auto-creates this the first time you connect any data source
# via IAM-role-based access — not created by this module, just extended
# with the permissions it needs for this specific pipeline.
data "aws_iam_role" "quicksight_service" {
  name = "aws-quicksight-service-role-v0"
}

data "aws_iam_policy_document" "quicksight_service_permissions" {
  statement {
    sid    = "EnrichedRead"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [var.enriched_bucket_arn, "${var.enriched_bucket_arn}/*"]
  }

  statement {
    sid       = "QuicksightResultsWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.enriched_bucket_arn}/athena-quicksight-results/*"]
  }

  statement {
    sid    = "GlueEnrichedRead"
    effect = "Allow"
    actions = [
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetDatabase",
      "glue:GetPartitions",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${var.account_id}:catalog",
      "arn:aws:glue:${var.region}:${var.account_id}:database/${var.enriched_database_name}",
      "arn:aws:glue:${var.region}:${var.account_id}:table/${var.enriched_database_name}/*",
    ]
  }

  statement {
    # Same catalog-wide requirement dbt's list_schemas() hit — Athena's own
    # schema-discovery calls this regardless of caller.
    sid       = "GlueListDatabases"
    effect    = "Allow"
    actions   = ["glue:GetDatabases"]
    resources = ["arn:aws:glue:${var.region}:${var.account_id}:catalog"]
  }

  statement {
    sid       = "LakeFormationDataAccess"
    effect    = "Allow"
    actions   = ["lakeformation:GetDataAccess"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "quicksight_service" {
  name   = "yt-pipeline-quicksight-enriched-access"
  role   = data.aws_iam_role.quicksight_service.name
  policy = data.aws_iam_policy_document.quicksight_service_permissions.json
}

# A dedicated workgroup, isolated from both the dashboard's and the
# pipeline's — same cost/query-tracking isolation rationale already
# documented in terraform/modules/athena for the dashboard's own workgroup.
resource "aws_athena_workgroup" "quicksight" {
  name = "yt-pipeline-quicksight"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${var.enriched_bucket_name}/athena-quicksight-results/"
    }
  }
}

resource "aws_quicksight_data_source" "athena" {
  data_source_id = "yt-pipeline-enriched"
  name           = "YT Pipeline - Enriched"
  type           = "ATHENA"

  parameters {
    athena {
      work_group = aws_athena_workgroup.quicksight.name
    }
  }

  permission {
    principal = var.quicksight_user_arn
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions",
    ]
  }
}

# Real column schemas (read directly from Glue after the first successful
# dbt build — the placeholder-column approach this module used before any
# tables existed is no longer needed). "categories" (array<string> on
# channel_analytics) is deliberately omitted: QuickSight's relational_table
# input_columns doesn't have a array/list column type, and it isn't needed
# for the KPI/ranking visuals this dataset drives.
locals {
  enriched_datasets = {
    trending_analytics = {
      name = "Trending Analytics"
      columns = [
        { name = "region", type = "STRING" },
        { name = "trending_date_parsed", type = "DATETIME" },
        { name = "total_videos", type = "INTEGER" },
        { name = "total_views", type = "INTEGER" },
        { name = "total_likes", type = "INTEGER" },
        { name = "total_comments", type = "INTEGER" },
        { name = "avg_engagement_rate", type = "DECIMAL" },
        { name = "avg_like_ratio", type = "DECIMAL" },
      ]
    }
    channel_analytics = {
      name = "Channel Analytics"
      columns = [
        { name = "channel_title", type = "STRING" },
        { name = "region", type = "STRING" },
        { name = "total_videos", type = "INTEGER" },
        { name = "total_views", type = "INTEGER" },
        { name = "avg_engagement_rate", type = "DECIMAL" },
        { name = "rank_in_region", type = "INTEGER" },
      ]
    }
    category_analytics = {
      name = "Category Analytics"
      columns = [
        { name = "region", type = "STRING" },
        { name = "trending_date_parsed", type = "DATETIME" },
        { name = "category_id", type = "STRING" },
        { name = "category_name", type = "STRING" },
        { name = "total_videos", type = "INTEGER" },
        { name = "total_views", type = "INTEGER" },
        { name = "view_share_pct", type = "DECIMAL" },
      ]
    }
  }
}

resource "aws_quicksight_data_set" "enriched" {
  for_each    = local.enriched_datasets
  data_set_id = "yt-pipeline-${each.key}"
  name        = each.value.name
  import_mode = "SPICE"

  physical_table_map {
    # physicalTableMap keys must match [0-9a-zA-Z-]* — underscores (as in
    # the actual table names) aren't allowed, confirmed via a real
    # ValidationException. This ID is purely an internal identifier, not
    # the table name itself, so any valid string works.
    physical_table_map_id = replace(each.key, "_", "-")
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = "AwsDataCatalog"
      schema          = var.enriched_database_name
      name            = each.key

      dynamic "input_columns" {
        for_each = each.value.columns
        content {
          name = input_columns.value.name
          type = input_columns.value.type
        }
      }
    }
  }

  permissions {
    principal = var.quicksight_user_arn
    actions = [
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:PassDataSet",
      "quicksight:DescribeIngestion",
      "quicksight:ListIngestions",
      "quicksight:UpdateDataSet",
      "quicksight:DeleteDataSet",
      "quicksight:CreateIngestion",
      "quicksight:CancelIngestion",
      "quicksight:UpdateDataSetPermissions",
    ]
  }
}

resource "aws_quicksight_refresh_schedule" "daily" {
  for_each    = aws_quicksight_data_set.enriched
  data_set_id = each.value.data_set_id
  schedule_id = "daily-refresh"

  schedule {
    refresh_type = "FULL_REFRESH"
    schedule_frequency {
      interval        = "DAILY"
      time_of_the_day = "06:00"
    }
  }
}
