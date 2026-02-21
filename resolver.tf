resource "aws_security_group" "relay_resolver_inbound" {
  for_each = local.relay_keys

  name        = "${var.name}-${each.key}-resolver-inbound-sg"
  description = "security group for relay inbound resolver endpoint"
  vpc_id      = aws_vpc.this[each.key].id

  ingress {
    description = "allow UDP DNS queries from site network"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.site_vpc_cidr]
  }

  ingress {
    description = "allow TCP DNS queries from site network"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.site_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-resolver-inbound-sg"
  })
}

resource "aws_route53_resolver_endpoint" "relay_inbound" {
  for_each = local.relay_keys

  name               = "${var.name}-${each.key}-inbound-resolver"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.relay_resolver_inbound[each.key].id]

  # マルチAZで片系障害を吸収できるよう、2つのIPを別サブネット（別AZ）に配置する。
  ip_address {
    subnet_id = aws_subnet.main[each.key].id
    ip        = var.relay_inbound_resolver_ips[each.key][0]
  }

  ip_address {
    subnet_id = aws_subnet.relay_secondary[each.key].id
    ip        = var.relay_inbound_resolver_ips[each.key][1]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-inbound-resolver"
  })
}
