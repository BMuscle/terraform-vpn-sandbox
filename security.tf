resource "aws_security_group" "eic" {
  for_each = toset(["service", "site_a", "site_b"])

  name        = "${var.name}-${each.key}-eic-sg"
  description = "security group for EC2 Instance Connect Endpoint"
  vpc_id      = aws_vpc.this[each.key].id

  ingress {
    description = "allow SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this[each.key].cidr_block]
  }

  egress {
    description = "allow SSH to VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this[each.key].cidr_block]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-eic-sg"
  })
}

resource "aws_security_group" "service_web" {
  name        = "${var.name}-service-web-sg"
  description = "security group for service web EC2"
  vpc_id      = aws_vpc.this["service"].id

  ingress {
    # PrivateLink経由の通信元は中継VPC内ENIのIPになるため、中継CIDRを許可する。
    description = "allow HTTP from service and relay networks"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [
      var.service_vpc_cidr,
      var.relay_vpc_cidrs["relay_a"],
      var.relay_vpc_cidrs["relay_b"],
    ]
  }

  ingress {
    description     = "allow SSH via EIC endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eic["service"].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-service-web-sg"
  })
}

resource "aws_security_group" "site_web" {
  for_each = local.site_keys

  name        = "${var.name}-${each.key}-web-sg"
  description = "security group for site web EC2"
  vpc_id      = aws_vpc.this[each.key].id

  ingress {
    description = "allow HTTP from same site network"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.site_vpc_cidr]
  }

  ingress {
    description     = "allow SSH via EIC endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eic[each.key].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-web-sg"
  })
}

resource "aws_security_group" "site_vpn_router" {
  for_each = local.site_keys

  name        = "${var.name}-${each.key}-vpn-router-sg"
  description = "security group for site vpn router EC2"
  vpc_id      = aws_vpc.this[each.key].id

  ingress {
    description     = "allow SSH via EIC endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.eic[each.key].id]
  }

  ingress {
    # ルータ経由の転送通信を許可する。これがないと拠点EC2からの中継VPC宛て通信がSGで落ちる。
    description = "allow forwarded traffic between site and relay networks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      var.site_vpc_cidr,
      var.relay_vpc_cidrs[local.site_to_relay[each.key]],
    ]
  }

  ingress {
    # AWS VPNの対向IPはトンネル生成時に払い出されるため、IP制限は持たずプロトコルで絞る。
    description = "allow IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allow ESP"
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-vpn-router-sg"
  })
}

resource "aws_security_group" "relay_endpoint" {
  for_each = local.relay_keys

  name        = "${var.name}-${each.key}-endpoint-sg"
  description = "security group for relay interface endpoint"
  vpc_id      = aws_vpc.this[each.key].id

  ingress {
    # 拠点A/Bは同一CIDRを使うため、拠点CIDRを共通で許可する。
    description = "allow HTTP from site network through VPN"
    from_port   = 80
    to_port     = 80
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
    Name = "${var.name}-${each.key}-endpoint-sg"
  })
}
