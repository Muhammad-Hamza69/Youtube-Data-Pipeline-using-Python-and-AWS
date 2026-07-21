output "data_source_arn" {
  value = aws_quicksight_data_source.athena.arn
}

output "workgroup_name" {
  value = aws_athena_workgroup.quicksight.name
}
