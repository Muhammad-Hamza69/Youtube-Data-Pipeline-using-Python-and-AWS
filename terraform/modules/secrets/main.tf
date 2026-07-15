resource "aws_secretsmanager_secret" "youtube_api_key" {
  name        = "yt-pipeline/youtube-api-key"
  description = "YouTube Data API v3 key used by the yt-ingest Lambda"

  # Without this, `terraform destroy` only schedules the secret for deletion
  # (default 30-day recovery window) instead of actually removing it — the
  # next `terraform apply` under the same name then fails with
  # "already scheduled for deletion". This project gets torn down and
  # rebuilt often enough that the default window causes real friction.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "youtube_api_key" {
  secret_id     = aws_secretsmanager_secret.youtube_api_key.id
  secret_string = var.youtube_api_key
}
