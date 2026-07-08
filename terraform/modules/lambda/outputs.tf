output "function_arns" {
  value = {
    yt-ingest          = aws_lambda_function.ingest.arn
    yt-json-to-parquet = aws_lambda_function.json_to_parquet.arn
    yt-data-quality    = aws_lambda_function.data_quality.arn
  }
}

output "function_names" {
  value = {
    yt-ingest          = aws_lambda_function.ingest.function_name
    yt-json-to-parquet = aws_lambda_function.json_to_parquet.function_name
    yt-data-quality    = aws_lambda_function.data_quality.function_name
  }
}
