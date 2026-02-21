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

variable "service_alb_secondary_az" {
  description = "secondary AZ used for multi-AZ resources in service and relay VPCs"
  type        = string
  default     = "ap-northeast-1c"

  validation {
    condition     = var.service_alb_secondary_az != var.az
    error_message = "service_alb_secondary_az must be different from az."
  }
}

variable "service_vpc_cidr" {
  description = "service vpc cidr block"
  type        = string
  default     = "10.0.0.0/24"

  validation {
    condition     = can(cidrsubnet(var.service_vpc_cidr, 1, 1))
    error_message = "service_vpc_cidr must be large enough to split into two subnets."
  }
}

variable "relay_vpc_cidrs" {
  description = "relay vpc cidr blocks"
  type        = map(string)
  default = {
    relay_a = "10.0.10.0/27"
    relay_b = "10.0.10.32/27"
  }

  validation {
    condition = alltrue([
      contains(keys(var.relay_vpc_cidrs), "relay_a"),
      contains(keys(var.relay_vpc_cidrs), "relay_b"),
      can(cidrsubnet(try(var.relay_vpc_cidrs["relay_a"], "10.0.10.0/27"), 1, 1)),
      can(cidrsubnet(try(var.relay_vpc_cidrs["relay_b"], "10.0.10.32/27"), 1, 1)),
    ])
    error_message = "relay_vpc_cidrs must include relay_a and relay_b and each must be large enough to split into two subnets."
  }
}

variable "site_vpc_cidr" {
  description = "site vpc cidr block"
  type        = string
  default     = "192.168.10.0/24"

  validation {
    condition     = can(cidrhost(var.site_vpc_cidr, 0)) && split("/", var.site_vpc_cidr)[1] == "24"
    error_message = "site_vpc_cidr must be a valid /24 CIDR (for this sandbox design)."
  }
}

variable "site_web_private_ip" {
  description = "fixed private IP address for site web instances"
  type        = string
  default     = "192.168.10.10"

  validation {
    condition = can(cidrhost("${var.site_web_private_ip}/32", 0)) && join(
      ".",
      slice(split(".", var.site_web_private_ip), 0, 3)
      ) == join(
      ".",
      slice(split(".", split("/", var.site_vpc_cidr)[0]), 0, 3)
    )
    error_message = "site_web_private_ip must be inside site_vpc_cidr."
  }
}

variable "site_vpn_router_private_ips" {
  description = "fixed private IP addresses for site vpn router instances"
  type        = map(string)
  default = {
    site_a = "192.168.10.11"
    site_b = "192.168.10.11"
  }

  validation {
    condition = alltrue([
      contains(keys(var.site_vpn_router_private_ips), "site_a"),
      contains(keys(var.site_vpn_router_private_ips), "site_b"),
      can(cidrhost("${var.site_vpn_router_private_ips["site_a"]}/32", 0)),
      can(cidrhost("${var.site_vpn_router_private_ips["site_b"]}/32", 0)),
      join(
        ".",
        slice(split(".", var.site_vpn_router_private_ips["site_a"]), 0, 3)
        ) == join(
        ".",
        slice(split(".", split("/", var.site_vpc_cidr)[0]), 0, 3)
      ),
      join(
        ".",
        slice(split(".", var.site_vpn_router_private_ips["site_b"]), 0, 3)
        ) == join(
        ".",
        slice(split(".", split("/", var.site_vpc_cidr)[0]), 0, 3)
      ),
      var.site_vpn_router_private_ips["site_a"] != var.site_web_private_ip,
      var.site_vpn_router_private_ips["site_b"] != var.site_web_private_ip,
    ])
    error_message = "site_vpn_router_private_ips must include site_a/site_b values in site_vpc_cidr and must not overlap site_web_private_ip."
  }
}

variable "service_web_bootstrap_enabled" {
  description = "enable service web bootstrap in user data"
  type        = bool
  default     = true
}

variable "relay_proxy_bootstrap_enabled" {
  description = "enable relay proxy bootstrap in user data"
  type        = bool
  default     = true
}

variable "site_web_resolv_conf_overwrite" {
  description = "overwrite /etc/resolv.conf on site web instances"
  type        = bool
  default     = true
}

variable "site_vpn_router_bootstrap_enabled" {
  description = "enable site vpn router bootstrap in user data"
  type        = bool
  default     = true
}

variable "site_web_content_html" {
  description = "html content served by site web python http server"
  type        = string
  default     = <<-EOT
  <!doctype html>
  <html>
    <head><meta charset="utf-8"><title>site web</title></head>
    <body>
      <h1>site web</h1>
      <p>served by python http.server on port 80</p>
    </body>
  </html>
  EOT
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

variable "mtls_ca_cert_path" {
  description = "path to CA certificate bundle file used by ALB trust store"
  type        = string
  default     = "certs/ca/ca.crt"
}

variable "site_client_cert_path" {
  description = "path to client certificate file uploaded to site web EC2"
  type        = string
  default     = "certs/clients/site-client.crt"
}

variable "site_client_key_path" {
  description = "path to client private key file uploaded to site web EC2"
  type        = string
  default     = "certs/clients/site-client.key"
}

variable "mtls_truststore_bucket_force_destroy" {
  description = "allow force destroy on trust store bucket for ephemeral environments"
  type        = bool
  default     = false
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
    relay_a = ["10.0.10.5", "10.0.10.21"]
    relay_b = ["10.0.10.43", "10.0.10.53"]
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
