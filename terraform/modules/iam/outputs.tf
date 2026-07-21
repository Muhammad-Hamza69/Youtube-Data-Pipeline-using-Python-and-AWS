output "sfn_role_arn" {
  value = aws_iam_role.sfn.arn
}

output "eventbridge_role_arn" {
  value = aws_iam_role.eventbridge.arn
}
