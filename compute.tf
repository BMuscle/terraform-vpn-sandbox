data "aws_ami" "amazon_linux_arm64" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-6.1-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "service_web" {
  ami                         = data.aws_ami.amazon_linux_arm64.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.main["service"].id
  vpc_security_group_ids      = [aws_security_group.service_web.id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "${var.name}-service-web"
  })
}

resource "aws_instance" "site_web" {
  for_each = local.site_keys

  ami           = data.aws_ami.amazon_linux_arm64.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main[each.key].id
  # 中継プロキシからの逆方向通信先を固定化するため、拠点WebのIPを固定する。
  private_ip                  = cidrhost(var.site_vpc_cidr, 10)
  vpc_security_group_ids      = [aws_security_group.site_web[each.key].id]
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-web"
  })
}

resource "aws_instance" "relay_proxy" {
  for_each = local.relay_keys

  ami                    = data.aws_ami.amazon_linux_arm64.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main[each.key].id
  private_ip             = var.relay_proxy_private_ips[each.key]
  vpc_security_group_ids = [aws_security_group.relay_proxy[each.key].id]
  # パッケージ導入のため外向きインターネットを使えるようにする。
  # 受信はSGで site/service CIDR のみ許可し、インターネット公開はしない。
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-proxy"
  })
}

resource "aws_instance" "site_vpn_router" {
  for_each = local.site_keys

  ami                         = data.aws_ami.amazon_linux_arm64.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.main[each.key].id
  vpc_security_group_ids      = [aws_security_group.site_vpn_router[each.key].id]
  associate_public_ip_address = true
  # ルータとして転送を担うため、送受信元チェックを無効化する。
  source_dest_check = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-vpn-router"
  })
}

resource "aws_eip" "site_vpn_router" {
  for_each = local.site_keys

  domain   = "vpc"
  instance = aws_instance.site_vpn_router[each.key].id

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-vpn-router-eip"
  })
}

resource "aws_ec2_instance_connect_endpoint" "this" {
  for_each = local.eic_keys

  subnet_id          = aws_subnet.main[each.key].id
  security_group_ids = [aws_security_group.eic[each.key].id]
  # EICE側のIPを送信元にすることで、EC2側SGをEICE SG参照で閉じられる。
  preserve_client_ip = false

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-eic-endpoint"
  })
}
