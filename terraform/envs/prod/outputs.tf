output "bucket_names" {
  value = module.s3.bucket_names
}

output "state_machine_arn" {
  value = module.stepfunctions.state_machine_arn
}

output "lambda_function_names" {
  value = module.lambda.function_names
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
