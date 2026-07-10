variable "lambda_role_arn" {
  type = string
}

variable "repository_url" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "glue_silver_db" {
  type = string
}

variable "athena_workgroup_name" {
  description = "Athena workgroup with a configured output location, used by yt-data-quality's read_sql_query calls (the 'primary' workgroup has no output location by default)."
  type        = string
}

variable "sns_topic_arn" {
  type = string
}

variable "dq_min_row_count" {
  type    = number
  default = 10
}

variable "dq_max_null_percent" {
  type    = number
  default = 5.0
}
