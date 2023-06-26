# Terraform module to dynamically generate a value to SSM Parameter Store

This module runs custom code and stores the result in an SSM parameter. It's useful to generate sensitive values on-the-fly.

## Usage

To generate a value, specify the code and the parameter name to store the result.

```
module "cf_key" {
    source  = "sashee/ssm-generated-value/aws"
    parameter_name = "/cfkey-${random_id.id.hex}"
    code = <<EOF
export const generate = async () => {
	return {
		value: ...,
		outputs: {
			...
		}
	};
}
export const cleanup = async () => {
    // ...
}
EOF
}
```

## Examples

### Generate keys for CloudFront public key

```
module "cf_key" {
	source  = "sashee/ssm-generated-value/aws"
	parameter_name = "/cfkey-${random_id.id.hex}"
	code = <<EOF
import crypto from "node:crypto";
import {promisify} from "node:util";

export const generate = async (event) => {
	const {publicKey, privateKey} = await promisify(crypto.generateKeyPair)(
		"rsa",
		{
			modulusLength: 2048,
			publicKeyEncoding: {
				type: 'spki',
				format: 'pem',
			},
			privateKeyEncoding: {
				type: 'pkcs8',
				format: 'pem',
			},
		},
	);
	return {
		value: privateKey,
		outputs: {
			publicKey,
		}
	};
}

export const cleanup = () => {};
EOF
}

resource "aws_cloudfront_public_key" "cf_key" {
  encoded_key = jsondecode(module.cf_key.outputs).publicKey
}
```

Use the private key in a Lambda function:

```
resource "aws_lambda_function" "lambda" {
# ...
    environment {
        variables = {
            CF_PRIVATE_KEY_PARAMETER = module.cf_key.parameter_name
            KEYPAIR_ID = aws_cloudfront_public_key.cf_key.id
        }
    }
}

data "aws_iam_policy_document" "backend" {
    statement {
        actions = [
          "ssm:GetParameter",
        ]
        resources = [
            module.cf_key.parameter_arn
        ]
    }
}
```

### Generate an Access Key for an IAM user

Implement the generate, cleanup functions and add the permissions necessary to manage keys:

```
module "access_key" {
	source  = "sashee/ssm-generated-value/aws"
	parameter_name = "/accesskey-${random_id.id.hex}"
	code = <<EOF
import {IAMClient, CreateAccessKeyCommand, ListAccessKeysCommand, DeleteAccessKeyCommand} from "@aws-sdk/client-iam";

const client = new IAMClient();
const UserName = "${aws_iam_user.signer.name}";

export const generate = async () => {
	const result = await client.send(new CreateAccessKeyCommand({
		UserName,
	}));
	return {
		value: result.AccessKey.SecretAccessKey,
		outputs: {
			AccessKeyId: result.AccessKey.AccessKeyId,
		}
	};
}

export const cleanup = async () => {
	const list = await client.send(new ListAccessKeysCommand({
		UserName,
	}));
	await Promise.all(list.AccessKeyMetadata.map(async ({AccessKeyId}) => {
		await client.send(new DeleteAccessKeyCommand({
			UserName,
			AccessKeyId,
		}));
	}));
}
EOF
	extra_permissions = <<EOF
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Action": [
				"iam:CreateAccessKey",
				"iam:ListAccessKeys",
				"iam:DeleteAccessKey"
			],
			"Effect": "Allow",
			"Resource": "${aws_iam_user.signer.arn}"
		}
	]
}
EOF
}
```

Use the results:

```
resource "aws_lambda_function" "backend" {
# ...
    environment {
        variables = {
            SECRET_ACCESS_KEY_PARAMETER = module.access_key.parameter_name
            ACCESS_KEY_ID = jsondecode(module.access_key.outputs).AccessKeyId
        }
    }
}
```
