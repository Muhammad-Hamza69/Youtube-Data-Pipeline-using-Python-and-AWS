# Reuses the exact permission statements from iam_permission/*.json (via the
# account/region-parameterized copies in terraform/templates/) — only the
# account ID substitution is new, the permission logic itself is untouched.

# ── Lambda execution role ───────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "yt-data-pipeline-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy" "lambda" {
  name = "yt-data-pipeline-lambda-access"
  role = aws_iam_role.lambda.id
  policy = templatefile("${var.templates_path}/lambda-access.json.tftpl", {
    region                     = var.region
    account_id                 = var.account_id
    youtube_api_key_secret_arn = var.youtube_api_key_secret_arn
  })
}

# Needed for package_type = "Image" Lambda functions.
resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Glue job role ────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "glue_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "yt-data-pipeline-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_trust.json
}

resource "aws_iam_role_policy" "glue" {
  name = "yt-data-pipeline-glue-access"
  role = aws_iam_role.glue.id
  policy = templatefile("${var.templates_path}/glue-access.json.tftpl", {
    region     = var.region
    account_id = var.account_id
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# ── Step Functions execution role ───────────────────────────────────────────

data "aws_iam_policy_document" "sfn_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "yt-data-pipeline-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_trust.json
}

resource "aws_iam_role_policy" "sfn" {
  name = "yt-data-pipeline-sfn-access"
  role = aws_iam_role.sfn.id
  policy = templatefile("${var.templates_path}/sfn-access.json.tftpl", {
    region     = var.region
    account_id = var.account_id
  })
}

# ── EventBridge → Step Functions execution role ─────────────────────────────

data "aws_iam_policy_document" "eventbridge_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge" {
  name               = "yt-data-pipeline-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_trust.json
}

data "aws_iam_policy_document" "eventbridge_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = ["arn:aws:states:${var.region}:${var.account_id}:stateMachine:yt-data-pipeline"]
  }
}

resource "aws_iam_role_policy" "eventbridge" {
  name   = "yt-data-pipeline-eventbridge-access"
  role   = aws_iam_role.eventbridge.id
  policy = data.aws_iam_policy_document.eventbridge_permissions.json
}
