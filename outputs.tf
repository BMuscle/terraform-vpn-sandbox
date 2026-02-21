output "service_nlb_dns_name" {
  description = "DNS name of service NLB"
  value       = aws_lb.service.dns_name
}

output "service_instance_id" {
  description = "service web instance id"
  value       = aws_instance.service_web.id
}

output "site_web_instance_ids" {
  description = "site web instance ids"
  value       = { for key, value in aws_instance.site_web : key => value.id }
}

output "site_vpn_router_instance_ids" {
  description = "site vpn router instance ids"
  value       = { for key, value in aws_instance.site_vpn_router : key => value.id }
}

output "site_vpn_router_public_ips" {
  description = "public ips used by customer gateways"
  value       = { for key, value in aws_eip.site_vpn_router : key => value.public_ip }
}

output "relay_vpc_endpoint_ids" {
  description = "interface endpoint ids in relay VPCs"
  value       = { for key, value in aws_vpc_endpoint.relay : key => value.id }
}

output "relay_vpc_endpoint_fixed_ips" {
  description = "fixed private IP addresses for relay interface endpoints"
  value       = var.endpoint_private_ips
}

output "vpn_connection_ids" {
  description = "site to relay vpn connection ids"
  value       = { for key, value in aws_vpn_connection.site_to_relay : key => value.id }
}

output "ec2_instance_connect_endpoint_ids" {
  description = "EC2 Instance Connect Endpoint ids"
  value       = { for key, value in aws_ec2_instance_connect_endpoint.this : key => value.id }
}

output "relay_inbound_resolver_endpoint_ids" {
  description = "inbound resolver endpoint ids in relay VPCs"
  value       = { for key, value in aws_route53_resolver_endpoint.relay_inbound : key => value.id }
}

output "relay_inbound_resolver_ips" {
  description = "fixed inbound resolver IPs in relay VPCs"
  value       = var.relay_inbound_resolver_ips
}

output "delegated_public_zone_name_servers" {
  description = "name servers of delegated public zone for private DNS name"
  value       = aws_route53_zone.delegated_private_dns.name_servers
}

output "private_dns_name_verification_record" {
  description = "TXT record information for endpoint service private DNS verification"
  value = local.endpoint_service_private_dns_configuration == null ? null : {
    name  = local.endpoint_service_private_dns_configuration.name
    type  = local.endpoint_service_private_dns_configuration.type
    value = local.endpoint_service_private_dns_configuration.value
  }
}
