data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "random_id" "id" {
  byte_length = 8
}

locals {
  parameterArn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${trimprefix(var.parameter_name, "/")}"
}

data "archive_file" "generate_value" {
  type        = "zip"
  output_path = "/tmp/ssm-generated-value-module-${random_id.id.hex}.zip"
  source {
    content  = var.code
    filename = "code.mjs"
  }
  source {
    content  = file("${path.module}/client.mjs")
    filename = "client.mjs"
  }
  source {
    content  = file("${path.module}/index.mjs")
    filename = "index.mjs"
  }
}

resource "aws_lambda_function" "generate_value" {
  function_name    = "ssm-generated-value-module-${random_id.id.hex}"
  filename         = data.archive_file.generate_value.output_path
  source_code_hash = data.archive_file.generate_value.output_base64sha256
  timeout          = 30
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  environment {
    variables = {
      PARAMETER_NAME : (var.use_secrets_manager ? aws_secretsmanager_secret.secret[0].id : var.parameter_name),
      USE_SECRETS_MANAGER : var.use_secrets_manager,
    }
  }
  role = aws_iam_role.generate_value_exec.arn
  depends_on = [
    # so that the delete permission is still there during destroy
    aws_iam_role_policy.generate_value,
  ]
}

resource "aws_secretsmanager_secret" "secret" {
  count = var.use_secrets_manager ? 1 : 0
  name = var.parameter_name
}

resource "aws_lambda_invocation" "generate_value" {
  function_name = aws_lambda_function.generate_value.function_name

  input           = "{}"
  lifecycle_scope = "CRUD"
  triggers = {

  }
  lifecycle {
    replace_triggered_by = [aws_lambda_function.generate_value]
  }
}

resource "aws_cloudwatch_log_group" "generate_value" {
  name              = "/aws/lambda/${aws_lambda_function.generate_value.function_name}"
  retention_in_days = 14
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
}

data "aws_iam_policy_document" "ssm" {
statement {
  actions = [
    "ssm:PutParameter",
    "ssm:DeleteParameter",
  ]

  resources = [
    local.parameterArn
  ]
  }
}

data "aws_iam_policy_document" "secrets_manager" {
  statement {
  actions = [
    "secretsmanager:DeleteSecret",
    "secretsmanager:PutSecretValue",
  ]

  resources = [
      try(aws_secretsmanager_secret.secret[0].arn, null)
    ]
  }
}

data "aws_iam_policy_document" "merge" {
  source_policy_documents = [
    data.aws_iam_policy_document.logs.json,
    (var.use_secrets_manager ? data.aws_iam_policy_document.secrets_manager.json : data.aws_iam_policy_document.ssm.json)
  ]
}

resource "aws_iam_role_policy" "generate_value" {
  role   = aws_iam_role.generate_value_exec.id
  policy = data.aws_iam_policy_document.merge.json
}

resource "aws_iam_role" "generate_value_exec" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

