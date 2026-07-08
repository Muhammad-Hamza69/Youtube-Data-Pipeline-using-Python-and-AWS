output "state_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.tfstate_lock.name
}

output "gha_plan_role_arn" {
  description = "Set as the AWS_PLAN_ROLE_ARN repo variable"
  value       = aws_iam_role.gha_plan.arn
}

output "gha_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN repo variable"
  value       = aws_iam_role.gha_deploy.arn
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
