terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

# Configured once module.eks exists (see eks.tf) — kubeconfig is derived
# dynamically via aws_eks_cluster_auth rather than a static token, so it
# stays valid across `terraform apply` runs without manual refresh.
#
# No kubernetes_* resources currently use this provider: the k8s/ manifests
# (Deployment, Service, ServiceAccount, Namespace) are applied by ArgoCD
# (module.argocd), not managed as Terraform state. This block exists so the
# dynamic auth data source is available if that changes later — it is
# reserved, not dead.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Used to install ArgoCD itself (module.argocd) via the argo-cd Helm chart.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
