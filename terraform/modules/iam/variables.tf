variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "templates_path" {
  description = "Path to terraform/templates (relative to the root module)"
  type        = string
  default     = "../../templates"
}
