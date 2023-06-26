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

