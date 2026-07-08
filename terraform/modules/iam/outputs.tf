output "lambda_role_arn" {
  value = aws_iam_role.lambda.arn
}

output "glue_role_arn" {
  value = aws_iam_role.glue.arn
}

output "sfn_role_arn" {
  value = aws_iam_role.sfn.arn
}

output "eventbridge_role_arn" {
  value = aws_iam_role.eventbridge.arn
}
