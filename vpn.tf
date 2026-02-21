resource "aws_vpn_gateway" "relay" {
  for_each = local.relay_keys

  vpc_id          = aws_vpc.this[each.key].id
  amazon_side_asn = var.relay_vgw_asns[each.key]

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-vgw"
  })
}

resource "aws_customer_gateway" "site" {
  for_each = local.site_keys

  bgp_asn    = var.site_customer_gateway_bgp_asns[each.key]
  ip_address = aws_eip.site_vpn_router[each.key].public_ip
  type       = "ipsec.1"

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-cgw"
  })
}

resource "aws_vpn_connection" "site_to_relay" {
  for_each = local.site_to_relay

  vpn_gateway_id      = aws_vpn_gateway.relay[each.value].id
  customer_gateway_id = aws_customer_gateway.site[each.key].id
  type                = "ipsec.1"
  # 拠点CIDRが重複する前提のため、BGP動的経路は使わず静的経路で閉じる。
  static_routes_only = true

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-vpn-connection"
  })
}

resource "aws_vpn_connection_route" "site_network" {
  for_each = local.site_to_relay

  # 2拠点とも同一CIDRだが、VPN接続自体が分離されているため個別に同じ経路を定義する。
  vpn_connection_id      = aws_vpn_connection.site_to_relay[each.key].id
  destination_cidr_block = var.site_vpc_cidr
}

resource "aws_route" "relay_to_site" {
  for_each = local.relay_to_site

  route_table_id         = aws_route_table.main[each.key].id
  destination_cidr_block = var.site_vpc_cidr
  gateway_id             = aws_vpn_gateway.relay[each.key].id
}

resource "aws_route" "site_to_relay" {
  for_each = local.site_to_relay

  route_table_id         = aws_route_table.main[each.key].id
  destination_cidr_block = var.relay_vpc_cidrs[each.value]
  # インスタンスIDはaws_routeで受けられないため、ルータEC2のENIを明示的に宛先にする。
  network_interface_id = aws_instance.site_vpn_router[each.key].primary_network_interface_id
}
