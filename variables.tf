variable "tags" {
  description = "default tags"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_account_id" {
  description = "AWS account id"
  type        = string
}

variable "env" {
  description = "environment name"
  type        = string
}
