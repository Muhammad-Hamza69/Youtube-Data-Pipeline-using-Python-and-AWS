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
  description = "From module.lambda.function_arns — ensures Terraform orders Lambda creation before the state machine"
  type        = map(string)
}

variable "glue_job_names" {
  description = "From module.glue outputs — ensures Terraform orders Glue job creation before the state machine"
  type        = map(string)
}
