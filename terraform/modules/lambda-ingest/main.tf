# image_tag has no default — it is passed by CI as -var="image_tag=${{ github.sha }}"
# so every apply is traceable to a commit and rolls the function to that build.

resource "aws_lambda_function" "this" {
  function_name = "yt-ingest"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "${var.repository_url}:${var.image_tag}"
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
