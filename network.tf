resource "aws_vpc" "this" {
  for_each = local.vpc_definitions

  cidr_block           = each.value.cidr
  enable_dns_support   = each.value.enable_dns_support
  enable_dns_hostnames = each.value.enable_dns_hostnames

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-vpc"
  })
}

resource "aws_subnet" "main" {
  for_each = local.vpc_definitions

  vpc_id = aws_vpc.this[each.key].id
  # 2AZ構成のVPCはCIDRを2分割し、primary subnetを先頭側に寄せる。
  cidr_block              = each.key == "service" || contains(local.relay_keys, each.key) ? cidrsubnet(each.value.cidr, 1, 0) : each.value.cidr
  availability_zone       = var.az
  map_public_ip_on_launch = each.value.igw

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-subnet"
  })
}

resource "aws_subnet" "service_alb_secondary" {
  # service系リソースの2AZ配置に使う第2サブネット。
  vpc_id                  = aws_vpc.this["service"].id
  cidr_block              = cidrsubnet(var.service_vpc_cidr, 1, 1)
  availability_zone       = var.service_alb_secondary_az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.name}-service-alb-secondary-subnet"
  })
}

resource "aws_subnet" "relay_secondary" {
  for_each = local.relay_keys

  # VPCEの2AZ構成を作るため、relay CIDRを2分割した第2サブネットを用意する。
  vpc_id                  = aws_vpc.this[each.key].id
  cidr_block              = cidrsubnet(var.relay_vpc_cidrs[each.key], 1, 1)
  availability_zone       = var.service_alb_secondary_az
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-secondary-subnet"
  })
}

resource "aws_route_table" "main" {
  for_each = local.vpc_definitions

  vpc_id = aws_vpc.this[each.key].id

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-rt"
  })
}

resource "aws_route_table_association" "main" {
  for_each = local.vpc_definitions

  subnet_id      = aws_subnet.main[each.key].id
  route_table_id = aws_route_table.main[each.key].id
}

resource "aws_route_table_association" "service_alb_secondary" {
  subnet_id      = aws_subnet.service_alb_secondary.id
  route_table_id = aws_route_table.main["service"].id
}

resource "aws_route_table_association" "relay_secondary" {
  for_each = local.relay_keys

  subnet_id      = aws_subnet.relay_secondary[each.key].id
  route_table_id = aws_route_table.main[each.key].id
}

resource "aws_internet_gateway" "this" {
  # サービスVPCと拠点VPCのみ外向き通信が必要。中継VPCにはIGWを置かない。
  for_each = {
    for key, value in local.vpc_definitions : key => value
    if value.igw
  }

  vpc_id = aws_vpc.this[each.key].id

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}-igw"
  })
}

resource "aws_route" "default_to_igw" {
  for_each = aws_internet_gateway.this

  route_table_id         = aws_route_table.main[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = each.value.id
}
