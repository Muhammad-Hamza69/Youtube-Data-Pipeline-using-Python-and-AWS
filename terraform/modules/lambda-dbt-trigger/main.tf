resource "aws_lambda_function" "this" {
  function_name = "yt-dbt-trigger"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "${var.repository_url}:${var.image_tag}"
  timeout       = 780 # Job creation + poll-to-completion; dbt build itself runs inside the pod, not this Lambda
  memory_size   = 256

  environment {
    variables = {
      EKS_CLUSTER_NAME     = var.eks_cluster_name
      EKS_CLUSTER_ENDPOINT = var.eks_cluster_endpoint
      EKS_CLUSTER_CA       = var.eks_cluster_ca
      K8S_NAMESPACE        = var.k8s_namespace
      K8S_SERVICE_ACCOUNT  = var.k8s_service_account
      DBT_IMAGE_URI        = var.dbt_image_uri
      ATHENA_WORKGROUP     = var.athena_workgroup_name
      RAW_DATABASE         = var.raw_database_name
      CURATED_DATABASE     = var.curated_database_name
      ENRICHED_DATABASE    = var.enriched_database_name
      CURATED_S3_DIR       = "s3://${var.curated_bucket_name}/"
      ENRICHED_S3_DIR      = "s3://${var.enriched_bucket_name}/"
      ATHENA_STAGING_DIR   = "s3://${var.raw_bucket_name}/athena-results/"
      AWS_REGION_NAME      = var.region
      SNS_ALERT_TOPIC_ARN  = var.sns_topic_arn
    }
  }
}
