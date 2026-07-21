variable "lambda_role_arn" {
  type = string
}

variable "repository_url" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "staging_bucket_name" {
  type = string
}

variable "raw_bucket_name" {
  type = string
}

variable "glue_raw_db" {
  type = string
}

variable "athena_workgroup_name" {
  type = string
}

variable "raw_table_statistics" {
  type    = string
  default = "raw_statistics"
}

variable "raw_table_reference" {
  type    = string
  default = "raw_reference_data"
}

variable "sns_topic_arn" {
  type = string
}
