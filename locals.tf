locals {
  # 構成差分をここに集約し、各リソースは for_each で共通化する。
  vpc_definitions = {
    service = {
      cidr                 = var.service_vpc_cidr
      igw                  = true
      enable_dns_support   = true
      enable_dns_hostnames = true
    }
    relay_a = {
      cidr = var.relay_vpc_cidrs["relay_a"]
      # 中継Proxyでdnf導入を可能にするため、IGW配下のPublic Subnetとして扱う。
      igw                  = true
      enable_dns_support   = true
      enable_dns_hostnames = true
    }
    relay_b = {
      cidr = var.relay_vpc_cidrs["relay_b"]
      # 中継Proxyでdnf導入を可能にするため、IGW配下のPublic Subnetとして扱う。
      igw                  = true
      enable_dns_support   = true
      enable_dns_hostnames = true
    }
    site_a = {
      # 拠点をオンプレ相当に寄せるため、AmazonProvidedDNSを無効化する。
      cidr                 = var.site_vpc_cidr
      igw                  = true
      enable_dns_support   = false
      enable_dns_hostnames = false
    }
    site_b = {
      # 拠点をオンプレ相当に寄せるため、AmazonProvidedDNSを無効化する。
      cidr                 = var.site_vpc_cidr
      igw                  = true
      enable_dns_support   = false
      enable_dns_hostnames = false
    }
  }

  relay_keys = toset(["relay_a", "relay_b"])
  site_keys  = toset(["site_a", "site_b"])
  eic_keys   = setunion(toset(["service"]), local.relay_keys, local.site_keys)
  tgw_keys   = setunion(toset(["service"]), local.relay_keys)

  # 拠点A/Bと中継A/Bを1:1で固定マッピングする。
  site_to_relay = {
    site_a = "relay_a"
    site_b = "relay_b"
  }

  # ルート作成時に逆引きが必要なため、上記の逆方向マップも持つ。
  relay_to_site = {
    relay_a = "site_a"
    relay_b = "site_b"
  }
}
