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

variable "bronze_bucket_name" {
  description = "Bronze S3 bucket crawled to populate the bronze Glue Catalog table that bronze_to_silver_statistics.py reads from."
  type        = string
}
