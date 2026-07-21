resource "aws_lambda_function" "this" {
  function_name = "yt-raw-transform"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "${var.repository_url}:${var.image_tag}"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      S3_BUCKET_STAGING   = var.staging_bucket_name
      S3_BUCKET_RAW       = var.raw_bucket_name
      GLUE_DB_RAW         = var.glue_raw_db
      ATHENA_WORKGROUP    = var.athena_workgroup_name
      RAW_TABLE_STATS     = var.raw_table_statistics
      RAW_TABLE_REF       = var.raw_table_reference
      SNS_ALERT_TOPIC_ARN = var.sns_topic_arn
    }
  }
}
