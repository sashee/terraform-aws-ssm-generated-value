variable "parameter_name" {
  type = string
	description = "The SSM parameter's name"
}

variable "code" {
  type = string
	description = "A Javascript source that exports a generate() and a cleanup() function"
}

variable "extra_permissions" {
  type = string
	default = null
	description = "JSON with the statements that will be attached to the function's role"
}
