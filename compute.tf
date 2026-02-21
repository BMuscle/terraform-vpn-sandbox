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
  for_each = local.service_subnet_ids

  ami                         = data.aws_ami.amazon_linux_arm64.id
  instance_type               = var.instance_type
  subnet_id                   = each.value
  vpc_security_group_ids      = [aws_security_group.service_web.id]
  associate_public_ip_address = true
  # Webサーバ初期化を手動作業から外すため、Nginx導入と起動をuser_dataで実施する。
  user_data = templatefile("${path.module}/templates/service-web-user-data.sh.tmpl", {
    bootstrap_enabled = var.service_web_bootstrap_enabled
  })
  user_data_replace_on_change = true

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
    Name = "${var.name}-service-web-${each.key}"
  })
}

resource "aws_instance" "site_web" {
  for_each = local.site_keys

  ami           = data.aws_ami.amazon_linux_arm64.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main[each.key].id
  # 中継プロキシからの逆方向通信先を固定化するため、拠点WebのIPを固定する。
  private_ip                  = var.site_web_private_ip
  vpc_security_group_ids      = [aws_security_group.site_web[each.key].id]
  associate_public_ip_address = true
  # 拠点EC2からmTLS通信を検証できるよう、クライアント証明書と秘密鍵を初期配置する。
  user_data = templatefile("${path.module}/templates/site-web-user-data.sh.tmpl", {
    client_cert_b64       = local.site_client_cert_b64
    client_key_b64        = local.site_client_key_b64
    resolver_ip_1         = var.relay_inbound_resolver_ips[local.site_to_relay[each.key]][0]
    resolver_ip_2         = var.relay_inbound_resolver_ips[local.site_to_relay[each.key]][1]
    resolv_conf_overwrite = var.site_web_resolv_conf_overwrite
    site_web_content_b64  = base64encode(var.site_web_content_html)
  })
  user_data_replace_on_change = true

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
  vpc_security_group_ids = [aws_security_group.relay_proxy[each.key].id]
  # パッケージ導入のため外向きインターネットを使えるようにする。
  # 受信はSGで site/service CIDR のみ許可し、インターネット公開はしない。
  associate_public_ip_address = true
  # 中継ProxyのNginx設定まで自動化し、apply直後に中継経路検証ができる状態にする。
  user_data = templatefile("${path.module}/templates/relay-proxy-user-data.sh.tmpl", {
    bootstrap_enabled      = var.relay_proxy_bootstrap_enabled
    site_to_service_domain = var.site_to_service_domain
    service_nlb_dns_name   = aws_lb.service.dns_name
    site_web_private_ip    = var.site_web_private_ip
  })
  user_data_replace_on_change = true

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
  private_ip                  = var.site_vpn_router_private_ips[each.key]
  vpc_security_group_ids      = [aws_security_group.site_vpn_router[each.key].id]
  associate_public_ip_address = true
  user_data = templatefile("${path.module}/templates/site-vpn-router-user-data.sh.tmpl", {
    bootstrap_enabled = var.site_vpn_router_bootstrap_enabled
  })
  user_data_replace_on_change = true
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

  depends_on = [
    aws_route53_resolver_endpoint.relay_inbound,
  ]
}
