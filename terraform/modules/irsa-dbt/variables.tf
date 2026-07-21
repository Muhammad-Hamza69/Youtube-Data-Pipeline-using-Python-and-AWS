variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Issuer URL, e.g. https://oidc.eks.<region>.amazonaws.com/id/XXXX (WITH the https:// prefix)"
  type        = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "namespace" {
  type    = string
  default = "data-pipeline"
}

variable "service_account_name" {
  type    = string
  default = "dbt"
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

variable "athena_workgroup_name" {
  type = string
}
