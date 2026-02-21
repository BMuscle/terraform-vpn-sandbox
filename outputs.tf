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
