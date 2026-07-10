resource "aws_lambda_function" "this" {
  function_name = "yt-json-to-parquet"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "${var.repository_url}:${var.image_tag}"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      S3_BUCKET_BRONZE     = var.bronze_bucket_name
      S3_BUCKET_SILVER     = var.silver_bucket_name
      GLUE_DB_SILVER       = var.glue_silver_db
      GLUE_TABLE_REFERENCE = var.glue_reference_table
      SNS_ALERT_TOPIC_ARN  = var.sns_topic_arn
    }
  }
}
