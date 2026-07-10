output "bucket_names" {
  value = module.s3.bucket_names
}

output "state_machine_arn" {
  value = module.stepfunctions.state_machine_arn
}

output "lambda_function_names" {
  value = {
    yt-ingest          = module.lambda_ingest.function_name
    yt-json-to-parquet = module.lambda_transform.function_name
    yt-data-quality    = module.lambda_dq.function_name
  }
}

# Read by each independent Lambda deploy workflow so an apply that isn't
# releasing a given Lambda can pass back its already-deployed tag unchanged,
# instead of drifting it back to a stale value.
output "ingest_image_uri" {
  value = module.lambda_ingest.image_uri
}

output "transform_image_uri" {
  value = module.lambda_transform.image_uri
}

output "dq_image_uri" {
  value = module.lambda_dq.image_uri
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "dashboard_role_arn" {
  value = module.irsa.dashboard_role_arn
}

output "dashboard_node_port_hint" {
  value = "Dashboard is exposed on NodePort 30080 on any EKS worker node once k8s/service.yaml is applied."
}
