output "youtube_api_key_secret_arn" {
  value = aws_secretsmanager_secret.youtube_api_key.arn
}

output "youtube_api_key_secret_name" {
  value = aws_secretsmanager_secret.youtube_api_key.name
}
