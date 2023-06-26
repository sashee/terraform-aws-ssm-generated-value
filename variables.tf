variable "parameter_name" {
  type = string
	description = "The SSM parameter's name"
}

variable "code" {
  type = string
	description = "A Javascript source that exports a generate() and a cleanup() function"
}

variable "extra_statements" {
	type = list(any)
	default = []
	description = "JSON statements that will be attached to the function's role"
}
