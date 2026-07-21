output "workgroup_name" {
  value = aws_athena_workgroup.dashboard.name
}

output "pipeline_workgroup_name" {
  value = aws_athena_workgroup.pipeline.name
}
