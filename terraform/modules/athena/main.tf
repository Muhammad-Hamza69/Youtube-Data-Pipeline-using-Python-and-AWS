# Separate workgroups per consumer — deliberately NOT the account's default
# "primary" workgroup (which Terraform can't cleanly "create fresh", AWS
# auto-provisions it per account) — isolates cost/query tracking per consumer.
# Both pin Athena engine version 3 explicitly: Iceberg tables (raw/curated/
# enriched, everywhere in this pipeline) are only queryable on engine v3, and
# nothing defaults there — omitting this is a silent, easy-to-miss failure.

resource "aws_athena_workgroup" "pipeline" {
  # Used by the raw-transform Lambda (awswrangler.athena.to_iceberg) and the
  # dbt Job running on EKS — both are core pipeline compute, sharing one
  # workgroup is fine; only the dashboard/QuickSight get their own for cost
  # isolation from ad hoc read traffic.
  name = "yt-pipeline-etl"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${var.raw_bucket_name}/athena-results/"
    }
  }
}

resource "aws_athena_workgroup" "dashboard" {
  name = "yt-pipeline-dashboard"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${var.enriched_bucket_name}/athena-dashboard-results/"
    }
  }
}
