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
  source                     = "../../modules/iam"
  region                     = var.region
  account_id                 = var.account_id
  youtube_api_key_secret_arn = module.secrets.youtube_api_key_secret_arn
}

module "glue" {
  source              = "../../modules/glue"
  glue_role_arn       = module.iam.glue_role_arn
  scripts_bucket_name = module.s3.bucket_names["scripts"]
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

module "lambda" {
  source                     = "../../modules/lambda"
  lambda_role_arn            = module.iam.lambda_role_arn
  repository_urls            = module.ecr.repository_urls
  image_tag                  = var.image_tag
  bronze_bucket_name         = module.s3.bucket_names["bronze"]
  silver_bucket_name         = module.s3.bucket_names["silver"]
  sns_topic_arn              = module.sns.topic_arn
  youtube_api_key_secret_arn = module.secrets.youtube_api_key_secret_arn
  glue_silver_db             = module.glue.database_names["silver"]
}

module "stepfunctions" {
  source               = "../../modules/stepfunctions"
  region               = var.region
  account_id           = var.account_id
  sfn_role_arn         = module.iam.sfn_role_arn
  lambda_function_arns = module.lambda.function_arns
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
