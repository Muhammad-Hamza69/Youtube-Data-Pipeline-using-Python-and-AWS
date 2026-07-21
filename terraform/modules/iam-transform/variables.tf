variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "staging_bucket_arn" {
  type = string
}

variable "raw_bucket_arn" {
  type = string
}

variable "glue_raw_db" {
  type = string
}

variable "athena_workgroup_name" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}
