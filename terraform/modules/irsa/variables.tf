variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Issuer URL, e.g. https://oidc.eks.<region>.amazonaws.com/id/XXXX (WITH the https:// prefix)"
  type        = string
}

variable "state_machine_arn" {
  type = string
}

variable "athena_workgroup_name" {
  type = string
}

variable "gold_bucket_arn" {
  type = string
}

variable "silver_glue_db_name" {
  type = string
}

variable "gold_glue_db_name" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "namespace" {
  type    = string
  default = "monitoring"
}

variable "service_account_name" {
  type    = string
  default = "dashboard-sa"
}
