# Three Lambda functions, all deployed as container images (package_type =
# "Image") instead of zip/layer bundles. image_tag has no default — it is
# passed by CI as -var="image_tag=${{ github.sha }}" so every apply is
# traceable to a commit and rolls the function to that build.

resource "aws_lambda_function" "ingest" {
  function_name = "yt-ingest"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "${var.repository_urls["yt-ingest"]}:${var.image_tag}"
  timeout       = 300
  memory_size   = 256

  environment {
    variables = {
      YOUTUBE_API_KEY_SECRET_ARN = var.youtube_api_key_secret_arn
      S3_BUCKET_BRONZE           = var.bronze_bucket_name
      YOUTUBE_REGIONS            = var.youtube_regions
      SNS_ALERT_TOPIC_ARN        = var.sns_topic_arn
    }
  }
}

resource "aws_lambda_function" "json_to_parquet" {
  function_name = "yt-json-to-parquet"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "${var.repository_urls["yt-json-to-parquet"]}:${var.image_tag}"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      S3_BUCKET_SILVER     = var.silver_bucket_name
      GLUE_DB_SILVER       = var.glue_silver_db
      GLUE_TABLE_REFERENCE = var.glue_reference_table
      SNS_ALERT_TOPIC_ARN  = var.sns_topic_arn
    }
  }
}

resource "aws_lambda_function" "data_quality" {
  function_name = "yt-data-quality"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "${var.repository_urls["yt-data-quality"]}:${var.image_tag}"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      GLUE_DB_SILVER      = var.glue_silver_db
      SNS_ALERT_TOPIC_ARN = var.sns_topic_arn
      DQ_MIN_ROW_COUNT    = tostring(var.dq_min_row_count)
      DQ_MAX_NULL_PERCENT = tostring(var.dq_max_null_percent)
    }
  }
}
