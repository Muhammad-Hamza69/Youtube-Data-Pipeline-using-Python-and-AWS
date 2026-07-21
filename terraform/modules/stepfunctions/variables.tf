variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "sfn_role_arn" {
  type = string
}

variable "templates_path" {
  type    = string
  default = "../../templates"
}

variable "lambda_function_arns" {
  description = "Merged from the per-Lambda modules' function_arn outputs — ensures Terraform orders Lambda creation before the state machine"
  type        = map(string)
}
