resource "aws_lb" "service" {
  # サービス公開はVPN/PrivateLink経由のみを想定し、NLBはinternalで構成する。
  name               = "${var.env}-svc-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = values(local.service_subnet_ids)

  tags = merge(local.tags, {
    Name = "${var.name}-service-nlb"
  })
}

resource "aws_lb" "service_alb" {
  # NLBの背後にInternal ALBを挟み、TLS終端とmTLS検証をALBで実施する。
  name               = "${var.env}-svc-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.service_alb.id]
  subnets            = values(local.service_subnet_ids)

  tags = merge(local.tags, {
    Name = "${var.name}-service-alb"
  })
}

resource "aws_lb_target_group" "service_backend" {
  name        = "${var.env}-svc-backend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this["service"].id
  target_type = "instance"

  health_check {
    enabled  = true
    path     = "/"
    port     = "traffic-port"
    protocol = "HTTP"
    matcher  = "200-399"
  }

  tags = merge(local.tags, {
    Name = "${var.name}-service-backend-tg"
  })
}

resource "aws_lb_target_group_attachment" "service_backend" {
  for_each = aws_instance.service_web

  target_group_arn = aws_lb_target_group.service_backend.arn
  target_id        = each.value.id
  port             = 80
}

resource "aws_lb_listener" "service_alb_http" {
  load_balancer_arn = aws_lb.service_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_backend.arn
  }
}

resource "aws_lb_listener" "service_alb_https" {
  load_balancer_arn = aws_lb.service_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.vpn.certificate_arn

  mutual_authentication {
    mode            = "verify"
    trust_store_arn = aws_lb_trust_store.service.arn
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_backend.arn
  }
}

resource "aws_lb_target_group" "service" {
  name        = "${var.env}-svc-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.this["service"].id
  target_type = "alb"

  health_check {
    enabled  = true
    path     = "/"
    port     = "80"
    protocol = "HTTP"
    matcher  = "200-399"
  }

  tags = merge(local.tags, {
    Name = "${var.name}-service-tg"
  })
}

resource "aws_lb_target_group_attachment" "service" {
  target_group_arn = aws_lb_target_group.service.arn
  target_id        = aws_lb.service_alb.arn
  port             = 80

  depends_on = [
    aws_lb_listener.service_alb_http,
  ]
}

resource "aws_lb_target_group" "service_https" {
  name        = "${var.env}-svc-https-tg"
  port        = 443
  protocol    = "TCP"
  vpc_id      = aws_vpc.this["service"].id
  target_type = "alb"

  health_check {
    enabled  = true
    path     = "/"
    port     = "80"
    protocol = "HTTP"
    matcher  = "200-399"
  }

  tags = merge(local.tags, {
    Name = "${var.name}-service-https-tg"
  })
}

resource "aws_lb_target_group_attachment" "service_https" {
  target_group_arn = aws_lb_target_group.service_https.arn
  target_id        = aws_lb.service_alb.arn
  port             = 443

  depends_on = [
    aws_lb_listener.service_alb_https,
  ]
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

resource "aws_lb_listener" "service_https" {
  load_balancer_arn = aws_lb.service.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_https.arn
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
  # 2AZにENIを作成するため、2つのサブネットを明示する。
  subnet_ids = values(local.relay_endpoint_subnet_ids[each.key])

  private_dns_enabled = var.enable_vpce_private_dns
  security_group_ids  = [aws_security_group.relay_endpoint[each.key].id]

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-service-endpoint"
  })

  depends_on = [
    aws_route53_record.delegation_ns,
    aws_vpc_endpoint_service_private_dns_verification.service,
  ]
}
