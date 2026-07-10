variable "lambda_role_arn" {
  type = string
}

variable "repository_urls" {
  description = "Map from module.ecr.repository_urls (must contain yt-ingest, yt-json-to-parquet, yt-data-quality)"
  type        = map(string)
}

variable "image_tag" {
  description = "Git SHA (or 'bootstrap' for the very first placeholder push) tagging the images to deploy"
  type        = string
}

variable "bronze_bucket_name" {
  type = string
}

variable "silver_bucket_name" {
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

variable "glue_silver_db" {
  type = string
}

variable "glue_reference_table" {
  type    = string
  default = "clean_reference_data"
}

variable "dq_min_row_count" {
  type    = number
  default = 10
}

variable "dq_max_null_percent" {
  type    = number
  default = 5.0
}

variable "athena_workgroup_name" {
  description = "Athena workgroup with a configured output location, used by yt-data-quality's read_sql_query calls (the 'primary' workgroup has no output location by default)."
  type        = string
}
