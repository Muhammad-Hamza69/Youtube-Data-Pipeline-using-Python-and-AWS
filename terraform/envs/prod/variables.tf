variable "region" {
  type    = string
  default = "us-east-1"
}

variable "account_id" {
  description = "Real target AWS account (corrects the 914216784354 placeholder baked into the original repo files)"
  type        = string
  default     = "300617413029"
}

variable "youtube_api_key" {
  description = "The existing YouTube API key from key.txt, kept as-is per project decision. Pass via -var, never commit to a .tfvars file."
  type        = string
  sensitive   = true
}

variable "image_tag" {
  description = "Git SHA tagging the Lambda/dashboard container images to deploy. No default on purpose — CI always passes this explicitly."
  type        = string
}

variable "eks_node_instance_type" {
  # See terraform/modules/eks/variables.tf for why this isn't t3.small anymore.
  type    = string
  default = "t3.medium"
}

variable "allowed_dashboard_cidr" {
  description = "CIDR allowed to reach the dashboard's NodePort (30080) on the EKS nodes. No default on purpose — the dashboard pod carries AWS read credentials via IRSA and must not be silently left open to the internet. Pass your office/VPN CIDR via -var or the DASHBOARD_ALLOWED_CIDR CI variable."
  type        = string
}
