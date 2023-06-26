variable "parameter_name" {
  type = string
	description = "The SSM parameter's name"
}

variable "code" {
  type = string
	description = "A Javascript source that exports a generate() function"
}
