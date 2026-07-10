variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "bronze_bucket_arn" {
  type = string
}

variable "silver_bucket_arn" {
  type = string
}

variable "glue_silver_db" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}
