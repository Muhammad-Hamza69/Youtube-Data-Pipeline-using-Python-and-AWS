resource "aws_secretsmanager_secret" "youtube_api_key" {
  name        = "yt-pipeline/youtube-api-key"
  description = "YouTube Data API v3 key used by the yt-ingest Lambda"
}

resource "aws_secretsmanager_secret_version" "youtube_api_key" {
  secret_id     = aws_secretsmanager_secret.youtube_api_key.id
  secret_string = var.youtube_api_key
}
