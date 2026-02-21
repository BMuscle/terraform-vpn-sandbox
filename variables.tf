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

variable "name" {
  description = "resource name prefix"
  type        = string
}

variable "az" {
  description = "single availability zone"
  type        = string
  default     = "ap-northeast-1a"
}

variable "service_vpc_cidr" {
  description = "service vpc cidr block"
  type        = string
  default     = "10.0.0.0/24"
}

variable "relay_vpc_cidrs" {
  description = "relay vpc cidr blocks"
  type        = map(string)
  default = {
    relay_a = "10.0.10.0/27"
    relay_b = "10.0.10.32/27"
  }
}

variable "site_vpc_cidr" {
  description = "site vpc cidr block"
  type        = string
  default     = "192.168.10.0/24"
}

variable "instance_type" {
  description = "ec2 instance type for web and vpn instances"
  type        = string
  default     = "t4g.nano"
}

variable "root_volume_size_gb" {
  description = "root ebs volume size in GB"
  type        = number
  default     = 10
}

variable "endpoint_private_ips" {
  description = "fixed private IP addresses for relay interface endpoints"
  type        = map(string)
  default = {
    relay_a = "10.0.10.4"
    relay_b = "10.0.10.36"
  }
}

variable "relay_vgw_asns" {
  description = "amazon side ASN for relay VGWs"
  type        = map(number)
  default = {
    relay_a = 64512
    relay_b = 64513
  }
}

variable "site_customer_gateway_bgp_asns" {
  description = "BGP ASNs for site customer gateways"
  type        = map(number)
  default = {
    site_a = 65010
    site_b = 65020
  }
}
