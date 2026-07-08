output "bucket_names" {
  value = { for k, v in aws_s3_bucket.this : k => v.bucket }
}

output "bucket_arns" {
  value = { for k, v in aws_s3_bucket.this : k => v.arn }
}
