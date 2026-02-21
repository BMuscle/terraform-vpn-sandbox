resource "aws_security_group" "eic" {
  for_each = local.eic_keys

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

resource "aws_security_group" "service_alb" {
  name        = "${var.name}-service-alb-sg"
  description = "security group for internal service ALB"
  vpc_id      = aws_vpc.this["service"].id

  ingress {
    # PrivateLink EndpointからNLB経由で到達するため、サービスVPC内からの到達を許可する。
    description = "allow HTTP from service network"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.service_vpc_cidr]
  }

  ingress {
    description = "allow HTTPS from service network"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.service_vpc_cidr]
  }

  egress {
    description = "allow HTTP to service web"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.service_vpc_cidr]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-service-alb-sg"
  })
}

resource "aws_security_group" "service_web" {
  name        = "${var.name}-service-web-sg"
  description = "security group for service web EC2"
  vpc_id      = aws_vpc.this["service"].id

  ingress {
    # サービスEC2はALB配下に限定し、直接の中継CIDR許可を持たない。
    description     = "allow HTTP from internal service ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.service_alb.id]
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
    description = "allow HTTP from same site network and mapped relay network"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [
      var.site_vpc_cidr,
      var.relay_vpc_cidrs[local.site_to_relay[each.key]],
    ]
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

resource "aws_security_group" "relay_proxy" {
  for_each = local.relay_keys

  name        = "${var.name}-${each.key}-proxy-sg"
  description = "security group for relay proxy EC2"
  vpc_id      = aws_vpc.this[each.key].id

  ingress {
    # 拠点 -> サービス方向: 拠点Webから中継プロキシへHTTPを受ける。
    description = "allow HTTP from site network"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.site_vpc_cidr]
  }

  ingress {
    # サービス -> 拠点方向: サービスWebから中継プロキシ固定IPへHTTPを受ける。
    description = "allow HTTP from service network"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.service_vpc_cidr]
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
    Name = "${var.name}-${each.key}-proxy-sg"
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

  ingress {
    description = "allow HTTPS from site network through VPN"
    from_port   = 443
    to_port     = 443
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
