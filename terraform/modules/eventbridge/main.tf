resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "yt-pipeline-schedule"
  description         = "Triggers YouTube data pipeline on a schedule"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "state_machine" {
  rule     = aws_cloudwatch_event_rule.schedule.name
  arn      = var.state_machine_arn
  role_arn = var.eventbridge_role_arn
}
