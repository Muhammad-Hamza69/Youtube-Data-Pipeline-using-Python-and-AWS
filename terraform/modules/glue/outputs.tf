output "database_names" {
  value = {
    raw      = aws_glue_catalog_database.raw.name
    curated  = aws_glue_catalog_database.curated.name
    enriched = aws_glue_catalog_database.enriched.name
  }
}
