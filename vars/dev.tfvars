aws_account_id          = "314211214994"
name                    = "vpn-sandbox-dev"
env                     = "dev"
private_dns_name        = "vpn.bmuscle.net"
site_to_service_domain  = "svc.vpn.bmuscle.net"
parent_public_zone_name = "bmuscle.net"
enable_vpce_private_dns = true
relay_proxy_private_ips = {
  relay_a = "10.0.10.7"
  relay_b = "10.0.10.39"
}
