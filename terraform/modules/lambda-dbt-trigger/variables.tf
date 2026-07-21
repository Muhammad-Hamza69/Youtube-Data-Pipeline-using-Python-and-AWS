variable "lambda_role_arn" {
  type = string
}

variable "repository_url" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "eks_cluster_endpoint" {
  type = string
}

variable "eks_cluster_ca" {
  type = string
}

variable "k8s_namespace" {
  type    = string
  default = "data-pipeline"
}

variable "k8s_service_account" {
  type    = string
  default = "dbt"
}

variable "dbt_image_uri" {
  type = string
}

variable "athena_workgroup_name" {
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

variable "raw_bucket_name" {
  type = string
}

variable "curated_bucket_name" {
  type = string
}

variable "enriched_bucket_name" {
  type = string
}

variable "region" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}
