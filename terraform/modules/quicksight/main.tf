# QuickSight is already subscribed/enabled on this account (a one-time
# console step Terraform can't cleanly automate — edition choice, account
# name, notification email) — this module only wires up the "connected
# datasets ready" half: an Athena data source + one SPICE dataset per
# Enriched table, refreshed daily. It deliberately does NOT hand-author an
# aws_quicksight_dashboard/aws_quicksight_analysis resource — that JSON
# `definition` is enormous and not meaningfully reviewable as Terraform
# diffs. Build the actual KPI dashboard once, manually, in the QuickSight
# console once these datasets show data — same kind of deliberate manual
# bootstrap exception k8s/argocd/application.yaml documents for itself.

data "aws_caller_identity" "current" {}

# NOTE: aws_quicksight_data_set / aws_quicksight_refresh_schedule have had
# real schema changes across aws provider versions (nested block names and
# required fields both shifted at various points) — verify this module's
# resource arguments against the pinned provider version's current docs
# (terraform providers schema -json, or the registry docs for that exact
# version) before the first real apply. This is flagged explicitly because
# confidence here is lower than the rest of this plan — QuickSight's
# Terraform support is the newest/most-changed corner of it.

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

locals {
  enriched_tables = {
    trending_analytics = "Trending Analytics"
    channel_analytics  = "Channel Analytics"
    category_analytics = "Category Analytics"
  }
}

resource "aws_quicksight_data_set" "enriched" {
  for_each    = local.enriched_tables
  data_set_id = "yt-pipeline-${each.key}"
  name        = each.value
  import_mode = "SPICE"

  physical_table_map {
    physical_table_map_id = each.key
    relational_table {
      data_source_arn = aws_quicksight_data_source.athena.arn
      catalog         = "AwsDataCatalog"
      schema          = var.enriched_database_name
      name            = each.key
      input_columns {
        name = "placeholder"
        type = "STRING"
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

  lifecycle {
    # relational_table.input_columns is normally auto-discovered by
    # QuickSight from the actual Athena table schema on first refresh —
    # the placeholder above just satisfies Terraform's schema requirement
    # at plan time; don't fight QuickSight over the real column list.
    ignore_changes = [physical_table_map]
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
