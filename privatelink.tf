resource "aws_lb" "service" {
  # サービス公開はVPN/PrivateLink経由のみを想定し、NLBはinternalで構成する。
  name               = "${var.env}-svc-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.main["service"].id]

  tags = merge(local.tags, {
    Name = "${var.name}-service-nlb"
  })
}

resource "aws_lb_target_group" "service" {
  name        = "${var.env}-svc-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.this["service"].id
  target_type = "instance"

  health_check {
    enabled  = true
    port     = "80"
    protocol = "TCP"
  }

  tags = merge(local.tags, {
    Name = "${var.name}-service-tg"
  })
}

resource "aws_lb_target_group_attachment" "service" {
  target_group_arn = aws_lb_target_group.service.arn
  target_id        = aws_instance.service_web.id
  port             = 80
}

resource "aws_lb_listener" "service_http" {
  load_balancer_arn = aws_lb.service.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service.arn
  }
}

resource "aws_vpc_endpoint_service" "service" {
  private_dns_name           = var.private_dns_name
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.service.arn]

  tags = merge(local.tags, {
    Name = "${var.name}-service-endpoint-service"
  })
}

resource "aws_vpc_endpoint_service_allowed_principal" "same_account" {
  vpc_endpoint_service_id = aws_vpc_endpoint_service.service.id
  principal_arn           = "arn:aws:iam::${var.aws_account_id}:root"
}

resource "aws_vpc_endpoint" "relay" {
  for_each = local.relay_keys

  vpc_id            = aws_vpc.this[each.key].id
  vpc_endpoint_type = "Interface"
  service_name      = aws_vpc_endpoint_service.service.service_name
  ip_address_type   = "ipv4"
  # SubnetConfigurations利用時でも、API互換のためSubnetIdsを明示しておく。
  subnet_ids = [aws_subnet.main[each.key].id]

  private_dns_enabled = var.enable_vpce_private_dns && local.endpoint_service_private_dns_configuration != null
  security_group_ids  = [aws_security_group.relay_endpoint[each.key].id]

  subnet_configuration {
    subnet_id = aws_subnet.main[each.key].id
    # 要件に合わせて中継VPC内の最若割当可能IPを明示固定する。
    ipv4 = var.endpoint_private_ips[each.key]
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-service-endpoint"
  })

  depends_on = [
    aws_route53_record.delegation_ns,
    aws_vpc_endpoint_service_private_dns_verification.service,
  ]
}
