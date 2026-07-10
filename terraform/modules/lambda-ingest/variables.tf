variable "lambda_role_arn" {
  type = string
}

variable "repository_url" {
  type = string
}

variable "image_tag" {
  description = "Git SHA (or 'bootstrap' for the very first placeholder push) tagging the image to deploy"
  type        = string
}

variable "bronze_bucket_name" {
  type = string
}

variable "youtube_regions" {
  type    = string
  default = "US,GB,CA,DE,FR,IN,JP,KR,MX,RU"
}

variable "sns_topic_arn" {
  type = string
}

variable "youtube_api_key_secret_arn" {
  type = string
}
