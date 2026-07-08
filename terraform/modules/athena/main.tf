# A separate workgroup for the monitoring dashboard's read-only Gold-table
# queries — deliberately NOT the account's default "primary" workgroup, which
# dq_lambda.py implicitly uses via wr.athena.read_sql_query(...) and which
# Terraform can't cleanly "create fresh" (AWS auto-provisions "primary" per
# account). Keeping the dashboard on its own workgroup avoids touching that
# unmanaged resource and isolates cost/query tracking.

resource "aws_athena_workgroup" "dashboard" {
  name = "yt-pipeline-dashboard"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.gold_bucket_name}/athena-dashboard-results/"
    }
  }
}
