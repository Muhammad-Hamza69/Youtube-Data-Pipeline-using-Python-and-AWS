variable "glue_role_arn" {
  type = string
}

variable "scripts_bucket_name" {
  type = string
}

variable "scripts_dir" {
  description = "Local path to glue_jobs/ (relative to the root module)"
  type        = string
  default     = "../../../glue_jobs"
}
