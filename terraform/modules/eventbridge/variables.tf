variable "state_machine_arn" {
  type = string
}

variable "eventbridge_role_arn" {
  type = string
}

variable "schedule_expression" {
  type    = string
  default = "rate(1 hour)"
}
