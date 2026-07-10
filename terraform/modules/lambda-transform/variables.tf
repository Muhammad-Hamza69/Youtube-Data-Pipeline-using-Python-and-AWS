variable "lambda_role_arn" {
  type = string
}

variable "repository_url" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "bronze_bucket_name" {
  type = string
}

variable "silver_bucket_name" {
  type = string
}

variable "glue_silver_db" {
  type = string
}

variable "glue_reference_table" {
  type    = string
  default = "clean_reference_data"
}

variable "sns_topic_arn" {
  type = string
}
