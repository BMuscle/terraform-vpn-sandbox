resource "aws_ec2_transit_gateway" "main" {
  description                     = "transit gateway for service and relay connectivity"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "disable"

  tags = merge(local.tags, {
    Name = "${var.name}-tgw"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = local.tgw_keys

  subnet_ids         = [aws_subnet.main[each.key].id]
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.this[each.key].id
  dns_support        = "enable"
  ipv6_support       = "disable"

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-tgw-attachment"
  })
}

resource "aws_ec2_transit_gateway_route_table" "service" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(local.tags, {
    Name = "${var.name}-service-tgw-rt"
  })
}

resource "aws_ec2_transit_gateway_route_table" "relay_a" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(local.tags, {
    Name = "${var.name}-relay-a-tgw-rt"
  })
}

resource "aws_ec2_transit_gateway_route_table" "relay_b" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(local.tags, {
    Name = "${var.name}-relay-b-tgw-rt"
  })
}

locals {
  tgw_route_table_ids = {
    service = aws_ec2_transit_gateway_route_table.service.id
    relay_a = aws_ec2_transit_gateway_route_table.relay_a.id
    relay_b = aws_ec2_transit_gateway_route_table.relay_b.id
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = local.tgw_keys

  # 各VPC attachmentを専用RTへ関連付け、伝播に頼らず明示ルーティングで分離する。
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = local.tgw_route_table_ids[each.key]
}

resource "aws_ec2_transit_gateway_route" "service_to_relay_a" {
  # serviceはrelay_aへ到達可能。
  destination_cidr_block         = var.relay_vpc_cidrs["relay_a"]
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["relay_a"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.service.id
}

resource "aws_ec2_transit_gateway_route" "service_to_relay_b" {
  # serviceはrelay_bへ到達可能。
  destination_cidr_block         = var.relay_vpc_cidrs["relay_b"]
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["relay_b"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.service.id
}

resource "aws_ec2_transit_gateway_route" "relay_a_to_service" {
  # relay_aはserviceのみに到達可能。relay_b宛ては作らない。
  destination_cidr_block         = var.service_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["service"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.relay_a.id
}

resource "aws_ec2_transit_gateway_route" "relay_b_to_service" {
  # relay_bはserviceのみに到達可能。relay_a宛ては作らない。
  destination_cidr_block         = var.service_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["service"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.relay_b.id
}

resource "aws_route" "service_to_relay_via_tgw" {
  for_each = local.relay_keys

  route_table_id         = aws_route_table.main["service"].id
  destination_cidr_block = var.relay_vpc_cidrs[each.key]
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "relay_to_service_via_tgw" {
  for_each = local.relay_keys

  route_table_id         = aws_route_table.main[each.key].id
  destination_cidr_block = var.service_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}
