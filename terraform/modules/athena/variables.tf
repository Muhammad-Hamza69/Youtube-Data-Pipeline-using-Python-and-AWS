variable "raw_bucket_name" {
  description = "Raw bucket used for the ETL workgroup's Athena query result output"
  type        = string
}

variable "enriched_bucket_name" {
  description = "Enriched bucket used for the dashboard workgroup's Athena query result output"
  type        = string
}
