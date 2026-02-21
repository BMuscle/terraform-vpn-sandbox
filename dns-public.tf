locals {
  endpoint_service_private_dns_configuration = try(
    one(aws_vpc_endpoint_service.service.private_dns_name_configuration),
    null
  )
}

data "aws_route53_zone" "parent_public" {
  name         = "${trimsuffix(var.parent_public_zone_name, ".")}."
  private_zone = false
}

resource "aws_route53_zone" "delegated_private_dns" {
  name = trimsuffix(var.private_dns_name, ".")

  tags = merge(local.tags, {
    Name = "${var.name}-delegated-public-zone"
  })
}

resource "aws_route53_record" "delegation_ns" {
  zone_id = data.aws_route53_zone.parent_public.zone_id
  name    = trimsuffix(var.private_dns_name, ".")
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.delegated_private_dns.name_servers
}

resource "aws_route53_record" "endpoint_service_private_dns_verification" {
  # private_dns_nameの所有検証は、委任先の子ゾーン側にTXTを作成する。
  count = local.endpoint_service_private_dns_configuration == null ? 0 : 1

  zone_id = aws_route53_zone.delegated_private_dns.zone_id
  name    = local.endpoint_service_private_dns_configuration.name
  type    = local.endpoint_service_private_dns_configuration.type
  ttl     = 300
  records = [local.endpoint_service_private_dns_configuration.value]
}

resource "aws_vpc_endpoint_service_private_dns_verification" "service" {
  count = local.endpoint_service_private_dns_configuration == null ? 0 : 1

  service_id = aws_vpc_endpoint_service.service.id

  depends_on = [
    aws_route53_record.delegation_ns,
    aws_route53_record.endpoint_service_private_dns_verification,
  ]
}
