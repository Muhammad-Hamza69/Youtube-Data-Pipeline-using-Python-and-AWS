variable "quicksight_user_arn" {
  description = "QuickSight user ARN (namespace 'default') to grant on the data source/datasets. No default — account-specific, pass at apply time like youtube_api_key."
  type        = string
}

variable "enriched_bucket_name" {
  type = string
}

variable "enriched_database_name" {
  type = string
}
