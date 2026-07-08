# Glue Data Catalog databases (bronze/silver/gold) + the two existing PySpark
# ETL jobs, uploaded unchanged — zero PySpark logic edits, this module only
# manages script deployment + job configuration.

resource "aws_glue_catalog_database" "bronze" {
  name = "yt_pipeline_bronze_db"
}

resource "aws_glue_catalog_database" "silver" {
  name = "yt_pipeline_silver_db"
}

resource "aws_glue_catalog_database" "gold" {
  name = "yt_pipeline_gold_db"
}

resource "aws_s3_object" "bronze_to_silver_script" {
  bucket = var.scripts_bucket_name
  key    = "glue_scripts/bronze_to_silver_statistics.py"
  source = "${var.scripts_dir}/bronze_to_silver_statistics.py"
  etag   = filemd5("${var.scripts_dir}/bronze_to_silver_statistics.py")
}

resource "aws_s3_object" "silver_to_gold_script" {
  bucket = var.scripts_bucket_name
  key    = "glue_scripts/silver_to_gold_analytics.py"
  source = "${var.scripts_dir}/silver_to_gold_analytics.py"
  etag   = filemd5("${var.scripts_dir}/silver_to_gold_analytics.py")
}

resource "aws_glue_job" "bronze_to_silver" {
  name              = "yt-data-pipeline-bronze-to-silver"
  role_arn          = var.glue_role_arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 60

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket_name}/${aws_s3_object.bronze_to_silver_script.key}"
    python_version  = "3"
  }
}

resource "aws_glue_job" "silver_to_gold" {
  name              = "yt-data-pipeline-silver-to-gold"
  role_arn          = var.glue_role_arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 60

  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket_name}/${aws_s3_object.silver_to_gold_script.key}"
    python_version  = "3"
  }
}
