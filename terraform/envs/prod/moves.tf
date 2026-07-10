# State-address updates for the Lambda module split (instructor feedback:
# "three lambdas should be separately managed"). These let Terraform re-map
# the 3 already-running Lambda functions onto their new per-Lambda modules
# in place, instead of destroying and recreating them.
#
# The old shared IAM role (module.iam.aws_iam_role.lambda) is intentionally
# NOT moved — it's replaced by 3 new least-privilege roles. Since each
# aws_lambda_function's `role` attribute isn't ForceNew, Terraform's
# dependency graph creates the 3 new roles and repoints the Lambdas at them
# before destroying the old shared role, all within one apply — no downtime.

moved {
  from = module.lambda.aws_lambda_function.ingest
  to   = module.lambda_ingest.aws_lambda_function.this
}

moved {
  from = module.lambda.aws_lambda_function.json_to_parquet
  to   = module.lambda_transform.aws_lambda_function.this
}

moved {
  from = module.lambda.aws_lambda_function.data_quality
  to   = module.lambda_dq.aws_lambda_function.this
}
