module "secrets" {
  source          = "../../modules/secrets"
  youtube_api_key = var.youtube_api_key
}

module "s3" {
  source     = "../../modules/s3"
  region     = var.region
  account_id = var.account_id
}

module "iam" {
  source     = "../../modules/iam"
  region     = var.region
  account_id = var.account_id
}

module "glue" {
  source              = "../../modules/glue"
  glue_role_arn       = module.iam.glue_role_arn
  scripts_bucket_name = module.s3.bucket_names["scripts"]
  bronze_bucket_name  = module.s3.bucket_names["bronze"]
}

module "ecr" {
  source = "../../modules/ecr"
}

module "sns" {
  source      = "../../modules/sns"
  alert_email = var.alert_email
}

module "athena" {
  source           = "../../modules/athena"
  gold_bucket_name = module.s3.bucket_names["gold"]
}

# ── Per-Lambda least-privilege IAM roles ────────────────────────────────────
# Split out of the old shared "iam" module's single lambda role so each
# Lambda only has the permissions it actually calls.

module "iam_ingest" {
  source                     = "../../modules/iam-ingest"
  bronze_bucket_arn          = module.s3.bucket_arns["bronze"]
  youtube_api_key_secret_arn = module.secrets.youtube_api_key_secret_arn
  sns_topic_arn              = module.sns.topic_arn
}

module "iam_transform" {
  source            = "../../modules/iam-transform"
  region            = var.region
  account_id        = var.account_id
  bronze_bucket_arn = module.s3.bucket_arns["bronze"]
  silver_bucket_arn = module.s3.bucket_arns["silver"]
  glue_silver_db    = module.glue.database_names["silver"]
  sns_topic_arn     = module.sns.topic_arn
}

module "iam_dq" {
  source                = "../../modules/iam-dq"
  region                = var.region
  account_id            = var.account_id
  silver_bucket_arn     = module.s3.bucket_arns["silver"]
  gold_bucket_arn       = module.s3.bucket_arns["gold"]
  glue_silver_db        = module.glue.database_names["silver"]
  athena_workgroup_name = module.athena.workgroup_name
  sns_topic_arn         = module.sns.topic_arn
}

# ── Per-Lambda independent modules ──────────────────────────────────────────
# Split out of the old shared "lambda" module so each Lambda's release cycle
# (image build/push + terraform apply) can be managed independently in CI.

module "lambda_ingest" {
  source                     = "../../modules/lambda-ingest"
  lambda_role_arn            = module.iam_ingest.role_arn
  repository_url             = module.ecr.repository_urls["yt-ingest"]
  image_tag                  = var.ingest_image_tag
  bronze_bucket_name         = module.s3.bucket_names["bronze"]
  sns_topic_arn              = module.sns.topic_arn
  youtube_api_key_secret_arn = module.secrets.youtube_api_key_secret_arn
}

module "lambda_transform" {
  source             = "../../modules/lambda-transform"
  lambda_role_arn    = module.iam_transform.role_arn
  repository_url     = module.ecr.repository_urls["yt-json-to-parquet"]
  image_tag          = var.transform_image_tag
  bronze_bucket_name = module.s3.bucket_names["bronze"]
  silver_bucket_name = module.s3.bucket_names["silver"]
  glue_silver_db     = module.glue.database_names["silver"]
  sns_topic_arn      = module.sns.topic_arn
}

module "lambda_dq" {
  source                = "../../modules/lambda-dq"
  lambda_role_arn       = module.iam_dq.role_arn
  repository_url        = module.ecr.repository_urls["yt-data-quality"]
  image_tag             = var.dq_image_tag
  glue_silver_db        = module.glue.database_names["silver"]
  athena_workgroup_name = module.athena.workgroup_name
  sns_topic_arn         = module.sns.topic_arn
}

module "stepfunctions" {
  source       = "../../modules/stepfunctions"
  region       = var.region
  account_id   = var.account_id
  sfn_role_arn = module.iam.sfn_role_arn
  lambda_function_arns = {
    yt-ingest          = module.lambda_ingest.function_arn
    yt-json-to-parquet = module.lambda_transform.function_arn
    yt-data-quality    = module.lambda_dq.function_arn
  }
  glue_job_names = {
    bronze_to_silver = module.glue.bronze_to_silver_job_name
    silver_to_gold   = module.glue.silver_to_gold_job_name
  }
}

module "eventbridge" {
  source               = "../../modules/eventbridge"
  state_machine_arn    = module.stepfunctions.state_machine_arn
  eventbridge_role_arn = module.iam.eventbridge_role_arn
}

module "eks" {
  source                 = "../../modules/eks"
  region                 = var.region
  account_id             = var.account_id
  node_instance_type     = var.eks_node_instance_type
  allowed_dashboard_cidr = var.allowed_dashboard_cidr
}

module "irsa" {
  source                = "../../modules/irsa"
  cluster_name          = module.eks.cluster_name
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.oidc_provider_url
  state_machine_arn     = module.stepfunctions.state_machine_arn
  athena_workgroup_name = module.athena.workgroup_name
  gold_bucket_arn       = module.s3.bucket_arns["gold"]
  silver_glue_db_name   = module.glue.database_names["silver"]
  gold_glue_db_name     = module.glue.database_names["gold"]
  account_id            = var.account_id
  region                = var.region
}

# GitOps for the dashboard (instructor feedback: "Go with Argo CD"). Watches
# k8s/ in this repo — see k8s/argocd/application.yaml, applied once manually
# per DEPLOYMENT.md's bootstrap steps.
module "argocd" {
  source     = "../../modules/argocd"
  depends_on = [module.eks]
}
