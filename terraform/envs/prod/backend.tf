# Must match terraform/bootstrap's state_bucket_name / lock_table_name
# outputs exactly. Backend blocks can't use variables, so these are literal —
# update both places together if you ever rename the backend bucket/table.

terraform {
  backend "s3" {
    bucket         = "yt-pipeline-tfstate-us-east-1-300617413029"
    key            = "envs/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "yt-pipeline-tfstate-lock"
    encrypt        = true
  }
}
