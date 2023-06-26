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
    content  = <<EOF
import crypto from "node:crypto";
import {SSMClient, PutParameterCommand, DeleteParameterCommand} from "@aws-sdk/client-ssm";
import {promisify} from "node:util";
import {generate} from "./code.mjs";

export const handler = async (event) => {
	const parameterName = process.env.SSM_PARAMETER;
	const client = new SSMClient();
	if (event.tf.action === "delete") {
		await client.send(new DeleteParameterCommand({
			Name: parameterName,
		}));
	}
	if (event.tf.action === "create") {
		const {value, outputs} = await generate();
		await client.send(new PutParameterCommand({
			Name: parameterName,
			Value: value,
			Type: "SecureString",
		}));
		return outputs;
	}
}
EOF
    filename = "index.mjs"
  }
}

resource "aws_lambda_function" "generate_value" {
  function_name    = "ssm-generated-value-module-${random_id.id.hex}"
  filename         = data.archive_file.generate_value.output_path
  source_code_hash = data.archive_file.generate_value.output_base64sha256
  timeout = 30
  handler = "index.handler"
  runtime = "nodejs18.x"
  environment {
    variables = {
      SSM_PARAMETER: var.parameter_name,
    }
  }
  role    = aws_iam_role.generate_value_exec.arn
	depends_on = [
		# so that the delete permission is still there during destroy
    aws_iam_role_policy.generate_value
  ]
}

resource "aws_lambda_invocation" "generate_value" {
  function_name = aws_lambda_function.generate_value.function_name

  input = "{}"
	lifecycle_scope = "CRUD"
	triggers = {
		
	}
  lifecycle {
    replace_triggered_by = [aws_lambda_function.generate_value]
  }
}

data "aws_iam_policy_document" "generate_value" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
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

resource "aws_cloudwatch_log_group" "generate_value" {
  name              = "/aws/lambda/${aws_lambda_function.generate_value.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "generate_value" {
  role   = aws_iam_role.generate_value_exec.id
  policy = data.aws_iam_policy_document.generate_value.json
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
