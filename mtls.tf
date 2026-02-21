resource "aws_s3_bucket" "mtls_trust_store" {
  bucket        = local.mtls_trust_store_bucket_name
  force_destroy = var.mtls_truststore_bucket_force_destroy

  tags = merge(local.tags, {
    Name = "${var.name}-mtls-trust-store"
  })
}

resource "aws_s3_bucket_public_access_block" "mtls_trust_store" {
  bucket = aws_s3_bucket.mtls_trust_store.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "mtls_ca_bundle" {
  bucket       = aws_s3_bucket.mtls_trust_store.id
  key          = local.mtls_ca_bundle_object_key
  source       = var.mtls_ca_cert_path
  etag         = filemd5(var.mtls_ca_cert_path)
  content_type = "application/x-pem-file"
}

resource "aws_lb_trust_store" "service" {
  name                             = "${var.env}-svc-trust-store"
  ca_certificates_bundle_s3_bucket = aws_s3_object.mtls_ca_bundle.bucket
  ca_certificates_bundle_s3_key    = aws_s3_object.mtls_ca_bundle.key
}

resource "aws_acm_certificate" "vpn" {
  domain_name       = var.private_dns_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, {
    Name = "${var.name}-vpn-cert"
  })
}

resource "aws_route53_record" "vpn_cert_validation" {
  for_each = {
    for option in aws_acm_certificate.vpn.domain_validation_options : option.domain_name => {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.delegated_private_dns.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.value]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "vpn" {
  certificate_arn         = aws_acm_certificate.vpn.arn
  validation_record_fqdns = [for record in aws_route53_record.vpn_cert_validation : record.fqdn]

  depends_on = [
    aws_route53_record.delegation_ns,
  ]
}
