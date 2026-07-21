# Role for yt-dbt-trigger — a small Lambda that creates a Kubernetes Job on
# the EKS cluster (running dbt), polls it to completion, and raises on
# failure so Step Functions' standard Catch handles it like any other Task —
# no exotic Step Functions<->EKS integration, no separate Choice state.
#
# This role only needs eks:DescribeCluster (to fetch the cluster's API
# endpoint + CA cert for the Kubernetes API calls) plus an EKS access entry
# (terraform/modules/eks) mapping it to namespace-scoped RBAC — the actual
# dbt workload's AWS permissions (Athena/Glue/S3/LF) live on the separate
# dbt IRSA role (terraform/modules/irsa-dbt), not here. Same split as ECS's
# execution-role/task-role convention, applied to the control-plane-vs-
# data-plane boundary between "can create a Job" and "can do what the Job's
# pod does."

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "yt-pipeline-lambda-dbt-trigger-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "DescribeEksCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [var.eks_cluster_arn]
  }

  statement {
    sid       = "SNSAccess"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "yt-pipeline-lambda-dbt-trigger-access"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

resource "aws_iam_role_policy_attachment" "basic_exec" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
