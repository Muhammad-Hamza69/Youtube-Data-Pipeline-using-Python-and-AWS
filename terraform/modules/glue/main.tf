# Glue Data Catalog databases only — raw/curated/enriched. No crawler, no
# Glue Jobs: Iceberg tables register their own schema in the Catalog as a
# side effect of CREATE TABLE/CTAS (via awswrangler.to_iceberg in the
# raw-transform Lambda, or dbt-athena for curated/enriched), so there's no
# raw-file-scanning discovery step left for a crawler to perform, and no
# PySpark ETL left for a Glue Job to run.

resource "aws_glue_catalog_database" "raw" {
  name = "yt_pipeline_raw_db"
}

resource "aws_glue_catalog_database" "curated" {
  name = "yt_pipeline_curated_db"
}

resource "aws_glue_catalog_database" "enriched" {
  name = "yt_pipeline_enriched_db"
}
