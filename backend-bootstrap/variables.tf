variable "aws_region" {
  description = "AWS region for backend bucket"
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "tf014"
}