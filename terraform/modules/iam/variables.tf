variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "youtube_api_key_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the YouTube API key (from the secrets module)"
  type        = string
}

variable "templates_path" {
  description = "Path to terraform/templates (relative to the root module)"
  type        = string
  default     = "../../templates"
}
