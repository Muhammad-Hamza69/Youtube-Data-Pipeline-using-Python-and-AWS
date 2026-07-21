variable "region" {
  type = string
}

variable "node_instance_type" {
  # t3.small (2GB RAM) proved too tight for kubelet+containerd+kube-proxy+VPC-CNI
  # to all start reliably — the CNI's ipamd process kept timing out on its
  # readiness/liveness probes under resource pressure, causing intermittent
  # node group CREATE_FAILED. t3.medium (4GB) gives real headroom.
  type    = string
  default = "t3.medium"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "allowed_dashboard_cidr" {
  description = "CIDR allowed to reach the dashboard's NodePort (30080). No default on purpose — this is a deliberate choice, not a rubber stamp. If your IP is stable, use your office/VPN CIDR; the app itself has no other protection at the network layer. If your IP changes across unrelated ISP ranges (making CIDR allowlisting impractical), 0.0.0.0/0 is acceptable ONLY because dashboard/app.py requires HTTP Basic Auth (TRIGGER_API_KEY) on every route except /healthz — the app-level secret is the real boundary in that case, not the network."
  type        = string
}

variable "cluster_name" {
  type    = string
  default = "yt-pipeline-dashboard"
}

variable "account_id" {
  type = string
}

variable "dbt_trigger_role_arn" {
  description = "IAM role ARN of the yt-dbt-trigger Lambda, granted namespace-scoped EKS access (see dbt_trigger access entry below)."
  type        = string
}

variable "dbt_namespace" {
  type    = string
  default = "data-pipeline"
}
