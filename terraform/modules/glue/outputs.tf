output "bronze_to_silver_job_name" {
  value = aws_glue_job.bronze_to_silver.name
}

output "silver_to_gold_job_name" {
  value = aws_glue_job.silver_to_gold.name
}

output "database_names" {
  value = {
    bronze = aws_glue_catalog_database.bronze.name
    silver = aws_glue_catalog_database.silver.name
    gold   = aws_glue_catalog_database.gold.name
  }
}
