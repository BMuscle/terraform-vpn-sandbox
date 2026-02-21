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

variable "relay_proxy_private_ips" {
  description = "fixed private IP addresses for relay proxy EC2 instances"
  type        = map(string)
  default = {
    relay_a = "10.0.10.7"
    relay_b = "10.0.10.39"
  }

  validation {
    condition = alltrue([
      contains(keys(var.relay_proxy_private_ips), "relay_a"),
      contains(keys(var.relay_proxy_private_ips), "relay_b"),
    ])
    error_message = "relay_proxy_private_ips must include relay_a and relay_b keys."
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

variable "private_dns_name" {
  description = "private DNS name for endpoint service"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+$", var.private_dns_name))
    error_message = "private_dns_name must be a valid DNS name."
  }
}

variable "site_to_service_domain" {
  description = "domain name used by site side HTTP access to service via relay proxy"
  type        = string
  default     = "svc.vpn.bmuscle.net"

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+$", var.site_to_service_domain))
    error_message = "site_to_service_domain must be a valid DNS name."
  }
}

variable "parent_public_zone_name" {
  description = "parent public hosted zone name used for NS delegation"
  type        = string
}

variable "relay_inbound_resolver_ips" {
  description = "fixed IP addresses for inbound resolver endpoints in relay VPCs"
  type        = map(list(string))
  default = {
    relay_a = ["10.0.10.5", "10.0.10.6"]
    relay_b = ["10.0.10.37", "10.0.10.38"]
  }

  validation {
    condition = alltrue([
      contains(keys(var.relay_inbound_resolver_ips), "relay_a"),
      contains(keys(var.relay_inbound_resolver_ips), "relay_b"),
      length(var.relay_inbound_resolver_ips["relay_a"]) == 2,
      length(var.relay_inbound_resolver_ips["relay_b"]) == 2,
    ])
    error_message = "relay_inbound_resolver_ips must include relay_a and relay_b, and each must have exactly two IPs."
  }
}

variable "enable_vpce_private_dns" {
  description = "enable private DNS on relay interface endpoints after endpoint service private DNS verification"
  type        = bool
  default     = false
}
