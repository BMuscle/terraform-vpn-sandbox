aws_account_id          = "314211214994"
name                    = "vpn-sandbox-dev"
env                     = "dev"
private_dns_name        = "vpn.bmuscle.net"
site_to_service_domain  = "svc.vpn.bmuscle.net"
parent_public_zone_name = "bmuscle.net"
enable_vpce_private_dns = true
mtls_ca_cert_path       = "certs/ca/ca.crt"
site_client_cert_path   = "certs/clients/site-client.crt"
site_client_key_path    = "certs/clients/site-client.key"
site_web_private_ip     = "192.168.10.200"
site_vpn_router_private_ips = {
  site_a = "192.168.10.210"
  site_b = "192.168.10.210"
}
