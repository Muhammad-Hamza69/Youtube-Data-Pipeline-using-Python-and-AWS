resource "aws_lambda_function" "this" {
  function_name = "yt-data-quality"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "${var.repository_url}:${var.image_tag}"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      GLUE_DB_SILVER      = var.glue_silver_db
      ATHENA_WORKGROUP    = var.athena_workgroup_name
      SNS_ALERT_TOPIC_ARN = var.sns_topic_arn
      DQ_MIN_ROW_COUNT    = tostring(var.dq_min_row_count)
      DQ_MAX_NULL_PERCENT = tostring(var.dq_max_null_percent)
    }
  }
}
