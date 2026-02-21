resource "aws_route53_zone" "relay_service_domain" {
  for_each = local.relay_keys

  # 同一FQDNをrelayごとに別ゾーンとして持ち、拠点ごとの問い合わせ先で解決先を分ける。
  name = trimsuffix(var.site_to_service_domain, ".")

  vpc {
    vpc_id = aws_vpc.this[each.key].id
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-private-zone"
  })
}

resource "aws_route53_record" "relay_service_domain_a" {
  for_each = local.relay_keys

  # site_aはrelay_aのInbound Resolver、site_bはrelay_bのInbound Resolverを使うため、
  # 同じFQDNでも問い合わせ元の経路で返却IPが変わる（split-horizon）。
  zone_id = aws_route53_zone.relay_service_domain[each.key].zone_id
  name    = trimsuffix(var.site_to_service_domain, ".")
  type    = "A"
  ttl     = 60
  records = [var.relay_proxy_private_ips[each.key]]
}
