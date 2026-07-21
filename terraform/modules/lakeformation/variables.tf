variable "admin_principal_arns" {
  description = "IAM principals to register as Lake Formation admins. Must include gha-deploy-role explicitly (see main.tf header comment) — do not rely on implicit first-apply admin."
  type        = list(string)
}

variable "raw_bucket_arn" {
  type = string
}

variable "curated_bucket_arn" {
  type = string
}

variable "enriched_bucket_arn" {
  type = string
}

variable "raw_database_name" {
  type = string
}

variable "curated_database_name" {
  type = string
}

variable "enriched_database_name" {
  type = string
}

variable "raw_transform_role_arn" {
  type = string
}

variable "dbt_role_arn" {
  type = string
}

variable "dashboard_role_arn" {
  type = string
}

variable "quicksight_role_arn" {
  description = "QuickSight data source's IAM role ARN, granted SELECT/DESCRIBE on enriched only. Null until the QuickSight module exists (phase 8) — the grant is skipped, not left dangling, until then."
  type        = string
  default     = null
}
