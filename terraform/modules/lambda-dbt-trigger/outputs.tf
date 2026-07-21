output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "image_uri" {
  value = aws_lambda_function.this.image_uri
}
