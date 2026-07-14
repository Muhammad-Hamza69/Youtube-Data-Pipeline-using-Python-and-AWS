# A small, dedicated EKS cluster whose only job is hosting the monitoring
# dashboard. Managed EC2 node group (not Fargate) — Fargate doesn't support
# NodePort services, which is what's needed to reach the dashboard on a fixed
# port. Public subnets keep this simple (no NAT gateway cost) since the only
# thing exposed is the dashboard's NodePort, restricted by security group.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "yt-pipeline-eks-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "yt-pipeline-eks-public-${count.index}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Cluster IAM role ─────────────────────────────────────────────────────────

data "aws_iam_policy_document" "eks_cluster_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "yt-pipeline-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_trust.json
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── Cluster ──────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  # No `version` pinned on purpose: a hardcoded minor version (e.g. "1.29")
  # eventually ages out of AWS's supported range and CreateCluster starts
  # rejecting it (InvalidParameterException: unsupported Kubernetes version).
  # Omitting it lets EKS use its own current default, which AWS keeps current.

  access_config {
    # Default (CONFIG_MAP-only) auth requires manually managing the aws-auth
    # ConfigMap to grant the node IAM role cluster access — nothing here does
    # that, so managed node group instances bootstrap fine at the OS level but
    # are never authorized to register with the API server, and the node
    # group eventually fails with CREATE_FAILED / "Unhealthy nodes". Under
    # API_AND_CONFIG_MAP, EKS automatically creates the access entry for a
    # *managed* node group's role, so no extra Terraform resource is needed.
    authentication_mode = "API_AND_CONFIG_MAP"
    # bootstrap_cluster_creator_admin_permissions is ForceNew — must be set
    # explicitly to match its actual current value (AWS defaulted it to true
    # when the cluster was first created), otherwise Terraform sees a diff
    # against the implicit `null` and replaces the entire cluster just to
    # change the authentication mode, which should be a pure in-place update.
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# bootstrap_cluster_creator_admin_permissions only grants admin to whoever's
# credentials actually ran CreateCluster. In the normal CI flow that's
# gha-deploy-role (deploy.yml applies this module), so this would be
# redundant — but nothing stops someone from applying this module locally
# (e.g. recovering from a full teardown) under a different IAM identity, which
# would leave gha-deploy-role with zero Kubernetes RBAC and break every
# subsequent workflow that runs kubectl (deploy-dashboard.yml's namespace/
# secret step). Granting it explicitly makes cluster access independent of
# who happened to run apply.
resource "aws_eks_access_entry" "gha_deploy" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = "arn:aws:iam::${var.account_id}:role/gha-deploy-role"
}

resource "aws_eks_access_policy_association" "gha_deploy_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.gha_deploy.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ── Cluster OIDC provider (for IRSA) ─────────────────────────────────────────

data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}

# ── Node group IAM role ──────────────────────────────────────────────────────

data "aws_iam_policy_document" "eks_node_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "yt-pipeline-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_trust.json
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── Node security group: NodePort 30080 + intra-cluster traffic ────────────

resource "aws_security_group" "nodes" {
  name   = "yt-pipeline-eks-nodes"
  vpc_id = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "nodes_self" {
  type              = "ingress"
  security_group_id = aws_security_group.nodes.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
}

resource "aws_security_group_rule" "nodes_from_cluster" {
  type                     = "ingress"
  security_group_id        = aws_security_group.nodes.id
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group_rule" "dashboard_nodeport" {
  type              = "ingress"
  security_group_id = aws_security_group.nodes.id
  from_port         = 30080
  to_port           = 30080
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_dashboard_cidr]
  description       = "Pipeline monitoring dashboard NodePort"
}

# ── Node group ───────────────────────────────────────────────────────────────
# A launch template is required to attach our custom security group (the
# NodePort/self/cluster rules above) — aws_eks_node_group has no direct
# vpc_security_group_ids argument.

resource "aws_launch_template" "nodes" {
  name_prefix = "yt-pipeline-eks-node-"

  # Supplying a custom launch template's own vpc_security_group_ids opts out
  # of EKS's automatic cluster-security-group attachment (that auto-attach
  # only happens when the launch template doesn't specify security groups at
  # all). Without the cluster SG here too, node/pod <-> control-plane traffic
  # is incomplete: CoreDNS can't watch the API server, stays NotReady forever,
  # and every pod's DNS resolution (including AWS API hostnames like
  # sts.amazonaws.com) fails as a result. Both SGs are required.
  vpc_security_group_ids = [aws_security_group.nodes.id, aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]

  # AWS's EKS docs require a hop limit of 2 (not the account default of 1)
  # for pod-based system components — the VPC CNI's aws-node daemonset in
  # particular — to reach the instance metadata service from a container
  # network namespace, even with hostNetwork: true. Without this, ipamd
  # hangs forever on its IMDS-dependent startup check, never opens its
  # gRPC port, and the node group fails with CREATE_FAILED "Unhealthy
  # nodes" regardless of instance size (confirmed: t3.small AND t3.medium
  # both failed identically until this was set).
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "yt-pipeline-eks-node" }
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "yt-pipeline-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.public[*].id
  instance_types  = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}
