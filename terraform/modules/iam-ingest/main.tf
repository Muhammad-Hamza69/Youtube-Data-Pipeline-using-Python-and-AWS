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
  name               = "yt-pipeline-lambda-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "StagingReadWrite"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [var.staging_bucket_arn, "${var.staging_bucket_arn}/*"]
  }

  statement {
    sid       = "SecretsManagerAccess"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.youtube_api_key_secret_arn]
  }

  statement {
    sid       = "SNSAccess"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "yt-pipeline-lambda-ingest-access"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

# Needed for package_type = "Image" Lambda functions.
resource "aws_iam_role_policy_attachment" "basic_exec" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
