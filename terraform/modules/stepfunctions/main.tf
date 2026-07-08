# State machine name "yt-data-pipeline" is referenced by the eventbridge
# module's IAM policy (states:StartExecution resource ARN) — do not rename
# without updating that module too.
#
# lambda_function_arns / glue_job_names aren't interpolated into the ASL
# directly (the ASL builds Lambda/Glue references by naming convention, same
# as the original file) — they're accepted here purely so Terraform's
# dependency graph creates the Lambdas + Glue jobs before this state machine.

resource "aws_sfn_state_machine" "pipeline" {
  name     = "yt-data-pipeline"
  role_arn = var.sfn_role_arn

  definition = templatefile("${var.templates_path}/pipeline_orchestration.json.tftpl", {
    region     = var.region
    account_id = var.account_id
  })

  depends_on = [var.lambda_function_arns, var.glue_job_names]
}
