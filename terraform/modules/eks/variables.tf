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
  description = "CIDR allowed to reach the dashboard's NodePort (30080). Set to your office/VPN CIDR — no default on purpose, since the dashboard pod carries AWS read credentials via IRSA and must not be silently left open to 0.0.0.0/0."
  type        = string
}

variable "cluster_name" {
  type    = string
  default = "yt-pipeline-dashboard"
}
