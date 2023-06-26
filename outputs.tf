output "parameter_arn" {
  value = local.parameterArn
	description = "The ARN of the created SSM parameter"
}

output "parameter_name" {
  value = var.parameter_name
	description = "The name of the created SSM parameter"
}

output "outputs" {
  value = aws_lambda_invocation.generate_value.result
	description = "The values the generate function return in the output in JSON-encoded form"
}
