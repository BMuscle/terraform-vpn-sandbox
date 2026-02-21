output "service_nlb_dns_name" {
  description = "DNS name of service NLB"
  value       = aws_lb.service.dns_name
}

output "service_alb_dns_name" {
  description = "DNS name of internal service ALB"
  value       = aws_lb.service_alb.dns_name
}

output "vpn_acm_certificate_arn" {
  description = "ACM certificate ARN for vpn domain"
  value       = aws_acm_certificate_validation.vpn.certificate_arn
}

output "mtls_trust_store_arn" {
  description = "ALB trust store ARN used for mTLS"
  value       = aws_lb_trust_store.service.arn
}

output "mtls_trust_store_bucket_name" {
  description = "S3 bucket name storing mTLS trust store bundle"
  value       = aws_s3_bucket.mtls_trust_store.bucket
}

output "service_instance_id" {
  description = "primary service web instance id"
  value       = aws_instance.service_web["primary"].id
}

output "service_instance_ids" {
  description = "service web instance ids by AZ role"
  value       = { for key, value in aws_instance.service_web : key => value.id }
}

output "site_web_instance_ids" {
  description = "site web instance ids"
  value       = { for key, value in aws_instance.site_web : key => value.id }
}

output "site_web_private_ip" {
  description = "fixed private IP address used by site web instances"
  value       = var.site_web_private_ip
}

output "relay_proxy_instance_ids" {
  description = "relay proxy instance ids"
  value       = { for key, value in aws_instance.relay_proxy : key => value.id }
}

output "relay_proxy_private_ips" {
  description = "private IP addresses for relay proxy instances"
  value       = { for key, value in aws_instance.relay_proxy : key => value.private_ip }
}

output "site_vpn_router_instance_ids" {
  description = "site vpn router instance ids"
  value       = { for key, value in aws_instance.site_vpn_router : key => value.id }
}

output "site_vpn_router_public_ips" {
  description = "public ips used by customer gateways"
  value       = { for key, value in aws_eip.site_vpn_router : key => value.public_ip }
}

output "transit_gateway_id" {
  description = "transit gateway id for service-relay connectivity"
  value       = aws_ec2_transit_gateway.main.id
}

output "transit_gateway_route_table_ids" {
  description = "transit gateway route table ids"
  value = {
    service = aws_ec2_transit_gateway_route_table.service.id
    relay_a = aws_ec2_transit_gateway_route_table.relay_a.id
    relay_b = aws_ec2_transit_gateway_route_table.relay_b.id
  }
}

output "relay_vpc_endpoint_ids" {
  description = "interface endpoint ids in relay VPCs"
  value       = { for key, value in aws_vpc_endpoint.relay : key => value.id }
}

output "relay_vpc_endpoint_dns_entries" {
  description = "dns entries for relay interface endpoints"
  value       = { for key, value in aws_vpc_endpoint.relay : key => value.dns_entry }
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

output "site_to_service_domain" {
  description = "domain name used by site web EC2 to access service through relay proxy"
  value       = var.site_to_service_domain
}

output "delegated_public_zone_name_servers" {
  description = "name servers of delegated public zone for private DNS name"
  value       = aws_route53_zone.delegated_private_dns.name_servers
}

output "private_dns_name_verification_record" {
  description = "TXT record information for endpoint service private DNS verification"
  value = {
    name  = local.endpoint_service_private_dns_configuration.name
    type  = local.endpoint_service_private_dns_configuration.type
    value = local.endpoint_service_private_dns_configuration.value
  }
}
