# terraform-vpn-sandbox

## 概要

拠点間VPNを使ったマルチテナント提供モデルを検証するためのTerraformです。

- 拠点側は単一AZ: `ap-northeast-1a`
- サービス/中継のVPN Endpoint経路は2AZ構成（primary: `ap-northeast-1a`, secondary: `ap-northeast-1c`）
- サービス側: サービスVPC 1つ + 中継VPC 2つ
- 拠点側: 拠点VPC 2つ（CIDR重複）
- 拠点 -> 中継: Site-to-Site VPN（中継VGW、拠点CGW）
- 中継 -> サービス: TGW（メイン経路）+ PrivateLink（併用検証）

`service_alb_secondary_az` の既定値は `ap-northeast-1c` です。アカウントで利用不可の場合は `vars/<env>.tfvars` で変更してください。

## ネットワーク構成

- サービスVPC: `10.0.0.0/24`
- 中継VPC-A: `10.0.10.0/27`
- 中継VPC-B: `10.0.10.32/27`
- サービスサブネット分割: `10.0.0.0/25`（primary）, `10.0.0.128/25`（secondary）
- 中継Aサブネット分割: `10.0.10.0/28`（primary）, `10.0.10.16/28`（secondary）
- 中継Bサブネット分割: `10.0.10.32/28`（primary）, `10.0.10.48/28`（secondary）
- 拠点VPC-A/B（重複）: `192.168.10.0/24`
- VPCEのENI IPはAWS自動割当（固定しない）
- 中継ProxyのENI IPはAWS自動割当（`terraform output relay_proxy_private_ips` で確認）

## 構築対象

- Amazon Linux 2023 + `t4g.nano` + `gp3 10GB` のEC2（サービスWebは2AZで2台、拠点/中継プロキシ/拠点VPNルータは単一AZ）
- サービスVPC内のInternal NLB（TCP/80,443）
- サービスVPC内のInternal ALB（HTTP/80, HTTPS/443, mTLS）
- `vpn.bmuscle.net` のACM証明書（DNS検証）
- ALB mTLSトラストストア用のS3バケット + `aws_lb_trust_store`
- PrivateLink Endpoint Service
- 中継VPC内のInterface VPC Endpoint（IP自動割当）
- TGW（service/relay_a/relay_b接続）
- 中継VPCごとのVGW
- 拠点ごとのCGW（拠点VPNルータEC2のEIPを利用）
- 拠点ごとのSite-to-Site VPN接続
- Route53 Resolver Inbound Endpoint（中継VPC）
- Route53 Private Hosted Zone（`svc.vpn.bmuscle.net` を中継VPCごとに作成）
- EC2 Instance Connect Endpoint（サービスVPC/中継VPC/拠点VPC）

## 手動作業

- 拠点VPNルータのIPsec接続情報投入（トンネルIP/PSK）とトンネル疎通確認
- 片系停止などの障害試験（検証作業）

## mTLS証明書の生成と管理

このリポジトリでは、mTLS用のCA証明書とクライアント証明書をローカル生成して管理します。
秘密鍵・証明書は `.gitignore` 済みです。

```bash
./scripts/generate-mtls-certs.sh
```

生成される主なファイル:

- `certs/ca/ca.crt`（ALBトラストストアにアップロード）
- `certs/ca/ca.key`
- `certs/clients/site-client.crt`（拠点EC2へTerraformで配置）
- `certs/clients/site-client.key`（拠点EC2へTerraformで配置）

補足:
- `vars/dev.tfvars` では上記パスを `mtls_ca_cert_path` / `site_client_cert_path` / `site_client_key_path` に設定済みです。
- `aws_instance.site_web` の `user_data` で `/etc/pki/mtls/client.crt` と `/etc/pki/mtls/client.key` が作成されます。
- `ec2-user` で `curl --cert/--key` 実行できるよう、`/etc/pki/mtls` 配下の所有者/権限を設定しています。

## Route53委任 + Inbound Resolver設定

この構成では以下の2種類の名前解決を併用します。

- `vpn.bmuscle.net`: PrivateLink（Endpoint Service private DNS, HTTPS + mTLS）
- `svc.vpn.bmuscle.net`: TGW + 中継Nginxプロキシ経路（拠点 -> サービス）

`svc.vpn.bmuscle.net` は既存互換のためHTTPのまま運用します。

- 親ゾーン: `bmuscle.net`
- 子ゾーン: `vpn.bmuscle.net`（Terraformで作成し、親ゾーンにNS委任）
- 中継VPC: Route53 Resolver Inbound Endpointを作成
- 中継VPC: `svc.vpn.bmuscle.net` のPrivate Hosted Zoneを中継ごとに作成

適用後に以下を確認します。

```bash
terraform output delegated_public_zone_name_servers
terraform output private_dns_name_verification_record
terraform output relay_inbound_resolver_ips
terraform output relay_vpc_endpoint_ids
terraform output relay_vpc_endpoint_dns_entries
terraform output relay_proxy_private_ips
terraform output site_to_service_domain
terraform output site_web_private_ip
terraform output vpn_acm_certificate_arn
terraform output mtls_trust_store_arn
terraform output mtls_trust_store_bucket_name
```

補足:
- 所有検証TXTは子ゾーン（`vpn.bmuscle.net`）に作成されます。
- `aws_vpc_endpoint_service_private_dns_verification` により、Endpoint Service側の`private_dns_name`検証を完了させます。
- `enable_vpce_private_dns` は段階的に切り替えます（初期は `false`）。

適用手順（推奨）:

1. 初回適用（検証レコード作成と検証完了待ち）

```bash
make apply env=dev
```

2. `vars/dev.tfvars` で `enable_vpce_private_dns = true` を設定
3. 再度適用（VPCE側private DNS有効化）

```bash
make apply env=dev
```

`vars/dev.tfvars` は初期状態で `enable_vpce_private_dns = false` です。段階適用後に `true` へ切り替えてください。

## EC2初期設定の自動化範囲

以下は Terraform の `user_data` で自動化済みです。

- `service_web`:
  - `nginx` インストール
  - `nginx` 起動/自動起動
- `relay_proxy`:
  - `nginx` インストール
  - `/etc/nginx/conf.d/relay-proxy.conf` 配置
  - `nginx -t` 実行と起動/自動起動
- `site_web`:
  - mTLSクライアント証明書/鍵配置
  - `/etc/resolv.conf` を中継Resolverに上書き
  - `site-http` systemdサービス配置と起動
- `site_vpn_router`:
  - `libreswan` インストール
  - `/etc/sysctl.d/99-vpn-router.conf` 配置
  - `net.ipv4.ip_forward=1` 有効化

確認コマンド:

```bash
# service_web
sudo systemctl status nginx --no-pager

# relay_proxy
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo cat /etc/nginx/conf.d/relay-proxy.conf

# site_web
sudo systemctl status site-http --no-pager
sudo cat /etc/resolv.conf
ls -l /etc/pki/mtls/

# 名前解決
nslookup svc.vpn.bmuscle.net
nslookup vpn.bmuscle.net
dig +short vpn.bmuscle.net
```

## リモート疎通確認

```bash
# 拠点 -> サービス（ドメインHTTP）
curl -I http://svc.vpn.bmuscle.net

# 拠点 -> サービス（PrivateLink + HTTPS + mTLS）
curl --cert /etc/pki/mtls/client.crt --key /etc/pki/mtls/client.key -I https://vpn.bmuscle.net

# 名前解決で返る各IPへの疎通確認（動的取得）
dig +short vpn.bmuscle.net
for ip in $(dig +short vpn.bmuscle.net); do
  curl --cert /etc/pki/mtls/client.crt --key /etc/pki/mtls/client.key -I --resolve vpn.bmuscle.net:443:${ip} https://vpn.bmuscle.net
done

# クライアント証明書なし（失敗すること）
curl -k -I https://vpn.bmuscle.net

# サービス -> 拠点（中継Proxy宛て）
RELAY_PROXY_IP_A="<terraform output relay_proxy_private_ips の relay_a>"
RELAY_PROXY_IP_B="<terraform output relay_proxy_private_ips の relay_b>"
curl -I http://${RELAY_PROXY_IP_A}
curl -I http://${RELAY_PROXY_IP_B}
```

補足:
- サービスWeb EC2はインターネットからの直接到達を許可していません。
- 拠点Web EC2は同一拠点CIDRに加えて、対応する中継CIDRからのHTTPを許可しています。
- 中継Proxy EC2はdnf導入のためPublic IPを持ちますが、受信はsite/service CIDRのみ許可しています。
- 中継間（relay_a <-> relay_b）はTGWルートテーブル分離により通信しません。

## 拠点間分離の検証

拠点A/Bは同一CIDRのため、対向拠点へ直接ルーティングできません。中継もTGWで分離しているため、以下の疎通は失敗する想定です。

```bash
# site_a から relay_b の中継Proxyへ（失敗すること）
curl --connect-timeout 3 http://${RELAY_PROXY_IP_B}

# site_b から relay_a の中継Proxyへ（失敗すること）
curl --connect-timeout 3 http://${RELAY_PROXY_IP_A}
```

## Libreswan設定手順（拠点VPNルータへSSH接続後）

この手順は `site_a` / `site_b` のVPNルータEC2でそれぞれ実施します。
`site_a` は中継CIDRに `10.0.10.0/27`、`site_b` は `10.0.10.32/27` を使ってください。

1. 変数をAWS CLIから取得して標準出力

前提:
- ローカル端末で実行する（このTerraformリポジトリ配下）
- `aws` / `terraform` / `jq` が利用可能
- `site_a` または `site_b` を選ぶ

```bash
SITE="site_a"
# SITE="site_b"

VPN_ID="$(terraform output -json vpn_connection_ids | jq -r --arg s "${SITE}" '.[$s]')"
SITE_EIP="$(terraform output -json site_vpn_router_public_ips | jq -r --arg s "${SITE}" '.[$s]')"

if [ "${SITE}" = "site_a" ]; then
  RELAY_SUBNETS="10.0.10.0/27"
else
  RELAY_SUBNETS="10.0.10.32/27"
fi

TUNNEL_OPTIONS_JSON="$(aws ec2 describe-vpn-connections \
  --vpn-connection-ids "${VPN_ID}" \
  --query 'VpnConnections[0].Options.TunnelOptions' \
  --output json)"

TUNNEL1_OUTSIDE_IP="$(jq -r '.[0].OutsideIpAddress' <<<"${TUNNEL_OPTIONS_JSON}")"
TUNNEL2_OUTSIDE_IP="$(jq -r '.[1].OutsideIpAddress' <<<"${TUNNEL_OPTIONS_JSON}")"
PSK1="$(jq -r '.[0].PreSharedKey // empty' <<<"${TUNNEL_OPTIONS_JSON}")"
PSK2="$(jq -r '.[1].PreSharedKey // empty' <<<"${TUNNEL_OPTIONS_JSON}")"

[ -n "${PSK1}" ] || PSK1="<Tunnel1のPSK>"
[ -n "${PSK2}" ] || PSK2="<Tunnel2のPSK>"

cat <<EOF
SITE_EIP="${SITE_EIP}"
SITE_SUBNET="192.168.10.0/24"
RELAY_SUBNETS="${RELAY_SUBNETS}"
TUNNEL1_OUTSIDE_IP="${TUNNEL1_OUTSIDE_IP}"
TUNNEL2_OUTSIDE_IP="${TUNNEL2_OUTSIDE_IP}"
PSK1="${PSK1}"
PSK2="${PSK2}"
EOF
```

2. Libreswanインストール状態を確認（Terraform `user_data` で実施済み）

```bash
rpm -q libreswan
```

3. IPフォワーディング設定を確認（Terraform `user_data` で実施済み）

```bash
cat /etc/sysctl.d/99-vpn-router.conf
sysctl net.ipv4.ip_forward
```

4. `/etc/ipsec.conf` を作成

```bash
sudo tee /etc/ipsec.conf >/dev/null <<EOF
config setup
  uniqueids=no

conn %default
  type=tunnel
  authby=secret
  keyexchange=ike
  ikev2=never
  left=%defaultroute
  leftid=${SITE_EIP}
  leftsubnet=${SITE_SUBNET}
  rightsubnets=${RELAY_SUBNETS}
  ike=aes128-sha1;modp2048
  phase2alg=aes128-sha1;modp2048
  ikelifetime=8h
  keylife=1h
  dpdaction=restart
  dpddelay=10
  dpdtimeout=30
  keyingtries=%forever
  auto=add

conn tunnel1
  also=%default
  right=${TUNNEL1_OUTSIDE_IP}

conn tunnel2
  also=%default
  right=${TUNNEL2_OUTSIDE_IP}
EOF
```

5. `/etc/ipsec.secrets` を作成

```bash
sudo tee /etc/ipsec.secrets >/dev/null <<EOF
${SITE_EIP} ${TUNNEL1_OUTSIDE_IP} : PSK "${PSK1}"
${SITE_EIP} ${TUNNEL2_OUTSIDE_IP} : PSK "${PSK2}"
EOF
sudo chmod 600 /etc/ipsec.secrets
```

6. Libreswanを起動し、自動起動を有効化

```bash
sudo systemctl enable --now ipsec
sudo systemctl status ipsec --no-pager
```

7. トンネルを明示的にロードして起動

```bash
sudo ipsec auto --add tunnel1
sudo ipsec auto --up tunnel1
sudo ipsec auto --add tunnel2
sudo ipsec auto --up tunnel2
```

8. トンネル状態を確認

```bash
sudo ipsec status
sudo ipsec trafficstatus
```

9. 疎通確認（拠点Webサーバー等から実施）

```bash
# site_a/site_b側の確認（TGW + 中継Proxy経路）
curl -I http://svc.vpn.bmuscle.net

# PrivateLink（HTTPS + mTLS）
curl --cert /etc/pki/mtls/client.crt --key /etc/pki/mtls/client.key -I https://vpn.bmuscle.net

# クライアント証明書なし（失敗すること）
curl -k -I https://vpn.bmuscle.net
```

補足:
- Terraform側で、拠点サブネットから中継CIDRへのルートはVPNルータEC2向けに設定済みです。
- SGで VPN 用に `UDP/500` `UDP/4500` `ESP(50)` を許可済みです。

## 使い方

```bash
make plan env=dev
make apply env=dev
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_acm_certificate.vpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.vpn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_customer_gateway.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/customer_gateway) | resource |
| [aws_ec2_instance_connect_endpoint.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_instance_connect_endpoint) | resource |
| [aws_ec2_transit_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway) | resource |
| [aws_ec2_transit_gateway_route.relay_a_to_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_route.relay_b_to_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_route.service_to_relay_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_route.service_to_relay_b](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route) | resource |
| [aws_ec2_transit_gateway_route_table.relay_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route_table) | resource |
| [aws_ec2_transit_gateway_route_table.relay_b](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route_table) | resource |
| [aws_ec2_transit_gateway_route_table.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route_table) | resource |
| [aws_ec2_transit_gateway_route_table_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_route_table_association) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_eip.site_vpn_router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_instance.relay_proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_instance.service_web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_instance.site_vpn_router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_instance.site_web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_lb.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb.service_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.service_alb_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.service_alb_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.service_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.service_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.service_backend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.service_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_lb_target_group_attachment.service_backend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_lb_target_group_attachment.service_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_lb_trust_store.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_trust_store) | resource |
| [aws_route.default_to_igw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.relay_to_service_via_tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.relay_to_site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.service_to_relay_via_tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.site_to_relay](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route53_record.delegation_ns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.endpoint_service_private_dns_verification](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.relay_service_domain_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.vpn_cert_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_resolver_endpoint.relay_inbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_zone.delegated_private_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_route53_zone.relay_service_domain](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_route_table.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.relay_secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.service_alb_secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_s3_bucket.mtls_trust_store](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.mtls_trust_store](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_object.mtls_ca_bundle](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_security_group.eic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.relay_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.relay_proxy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.relay_resolver_inbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.service_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.service_web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.site_vpn_router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.site_web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.relay_secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.service_alb_secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.relay](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint_service.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint_service) | resource |
| [aws_vpc_endpoint_service_allowed_principal.same_account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint_service_allowed_principal) | resource |
| [aws_vpc_endpoint_service_private_dns_verification.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint_service_private_dns_verification) | resource |
| [aws_vpn_connection.site_to_relay](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection) | resource |
| [aws_vpn_connection_route.site_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection_route) | resource |
| [aws_vpn_gateway.relay](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway) | resource |
| [aws_ami.amazon_linux_arm64](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_route53_zone.parent_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account id | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region | `string` | `"ap-northeast-1"` | no |
| <a name="input_az"></a> [az](#input\_az) | single availability zone | `string` | `"ap-northeast-1a"` | no |
| <a name="input_enable_vpce_private_dns"></a> [enable\_vpce\_private\_dns](#input\_enable\_vpce\_private\_dns) | enable private DNS on relay interface endpoints after endpoint service private DNS verification | `bool` | `false` | no |
| <a name="input_env"></a> [env](#input\_env) | environment name | `string` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | ec2 instance type for web and vpn instances | `string` | `"t4g.nano"` | no |
| <a name="input_mtls_ca_cert_path"></a> [mtls\_ca\_cert\_path](#input\_mtls\_ca\_cert\_path) | path to CA certificate bundle file used by ALB trust store | `string` | `"certs/ca/ca.crt"` | no |
| <a name="input_mtls_truststore_bucket_force_destroy"></a> [mtls\_truststore\_bucket\_force\_destroy](#input\_mtls\_truststore\_bucket\_force\_destroy) | allow force destroy on trust store bucket for ephemeral environments | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | resource name prefix | `string` | n/a | yes |
| <a name="input_parent_public_zone_name"></a> [parent\_public\_zone\_name](#input\_parent\_public\_zone\_name) | parent public hosted zone name used for NS delegation | `string` | n/a | yes |
| <a name="input_private_dns_name"></a> [private\_dns\_name](#input\_private\_dns\_name) | private DNS name for endpoint service | `string` | n/a | yes |
| <a name="input_relay_inbound_resolver_ips"></a> [relay\_inbound\_resolver\_ips](#input\_relay\_inbound\_resolver\_ips) | fixed IP addresses for inbound resolver endpoints in relay VPCs | `map(list(string))` | <pre>{<br>  "relay_a": [<br>    "10.0.10.5",<br>    "10.0.10.21"<br>  ],<br>  "relay_b": [<br>    "10.0.10.43",<br>    "10.0.10.53"<br>  ]<br>}</pre> | no |
| <a name="input_relay_proxy_bootstrap_enabled"></a> [relay\_proxy\_bootstrap\_enabled](#input\_relay\_proxy\_bootstrap\_enabled) | enable relay proxy bootstrap in user data | `bool` | `true` | no |
| <a name="input_relay_vgw_asns"></a> [relay\_vgw\_asns](#input\_relay\_vgw\_asns) | amazon side ASN for relay VGWs | `map(number)` | <pre>{<br>  "relay_a": 64512,<br>  "relay_b": 64513<br>}</pre> | no |
| <a name="input_relay_vpc_cidrs"></a> [relay\_vpc\_cidrs](#input\_relay\_vpc\_cidrs) | relay vpc cidr blocks | `map(string)` | <pre>{<br>  "relay_a": "10.0.10.0/27",<br>  "relay_b": "10.0.10.32/27"<br>}</pre> | no |
| <a name="input_root_volume_size_gb"></a> [root\_volume\_size\_gb](#input\_root\_volume\_size\_gb) | root ebs volume size in GB | `number` | `10` | no |
| <a name="input_service_alb_secondary_az"></a> [service\_alb\_secondary\_az](#input\_service\_alb\_secondary\_az) | secondary AZ used for multi-AZ resources in service and relay VPCs | `string` | `"ap-northeast-1c"` | no |
| <a name="input_service_vpc_cidr"></a> [service\_vpc\_cidr](#input\_service\_vpc\_cidr) | service vpc cidr block | `string` | `"10.0.0.0/24"` | no |
| <a name="input_service_web_bootstrap_enabled"></a> [service\_web\_bootstrap\_enabled](#input\_service\_web\_bootstrap\_enabled) | enable service web bootstrap in user data | `bool` | `true` | no |
| <a name="input_site_client_cert_path"></a> [site\_client\_cert\_path](#input\_site\_client\_cert\_path) | path to client certificate file uploaded to site web EC2 | `string` | `"certs/clients/site-client.crt"` | no |
| <a name="input_site_client_key_path"></a> [site\_client\_key\_path](#input\_site\_client\_key\_path) | path to client private key file uploaded to site web EC2 | `string` | `"certs/clients/site-client.key"` | no |
| <a name="input_site_customer_gateway_bgp_asns"></a> [site\_customer\_gateway\_bgp\_asns](#input\_site\_customer\_gateway\_bgp\_asns) | BGP ASNs for site customer gateways | `map(number)` | <pre>{<br>  "site_a": 65010,<br>  "site_b": 65020<br>}</pre> | no |
| <a name="input_site_to_service_domain"></a> [site\_to\_service\_domain](#input\_site\_to\_service\_domain) | domain name used by site side HTTP access to service via relay proxy | `string` | `"svc.vpn.bmuscle.net"` | no |
| <a name="input_site_vpc_cidr"></a> [site\_vpc\_cidr](#input\_site\_vpc\_cidr) | site vpc cidr block | `string` | `"192.168.10.0/24"` | no |
| <a name="input_site_vpn_router_bootstrap_enabled"></a> [site\_vpn\_router\_bootstrap\_enabled](#input\_site\_vpn\_router\_bootstrap\_enabled) | enable site vpn router bootstrap in user data | `bool` | `true` | no |
| <a name="input_site_vpn_router_private_ips"></a> [site\_vpn\_router\_private\_ips](#input\_site\_vpn\_router\_private\_ips) | fixed private IP addresses for site vpn router instances | `map(string)` | <pre>{<br>  "site_a": "192.168.10.11",<br>  "site_b": "192.168.10.11"<br>}</pre> | no |
| <a name="input_site_web_content_html"></a> [site\_web\_content\_html](#input\_site\_web\_content\_html) | html content served by site web python http server | `string` | `"<!doctype html>\n<html>\n  <head><meta charset=\"utf-8\"><title>site web</title></head>\n  <body>\n    <h1>site web</h1>\n    <p>served by python http.server on port 80</p>\n  </body>\n</html>\n"` | no |
| <a name="input_site_web_private_ip"></a> [site\_web\_private\_ip](#input\_site\_web\_private\_ip) | fixed private IP address for site web instances | `string` | `"192.168.10.10"` | no |
| <a name="input_site_web_resolv_conf_overwrite"></a> [site\_web\_resolv\_conf\_overwrite](#input\_site\_web\_resolv\_conf\_overwrite) | overwrite /etc/resolv.conf on site web instances | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | default tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_delegated_public_zone_name_servers"></a> [delegated\_public\_zone\_name\_servers](#output\_delegated\_public\_zone\_name\_servers) | name servers of delegated public zone for private DNS name |
| <a name="output_ec2_instance_connect_endpoint_ids"></a> [ec2\_instance\_connect\_endpoint\_ids](#output\_ec2\_instance\_connect\_endpoint\_ids) | EC2 Instance Connect Endpoint ids |
| <a name="output_mtls_trust_store_arn"></a> [mtls\_trust\_store\_arn](#output\_mtls\_trust\_store\_arn) | ALB trust store ARN used for mTLS |
| <a name="output_mtls_trust_store_bucket_name"></a> [mtls\_trust\_store\_bucket\_name](#output\_mtls\_trust\_store\_bucket\_name) | S3 bucket name storing mTLS trust store bundle |
| <a name="output_private_dns_name_verification_record"></a> [private\_dns\_name\_verification\_record](#output\_private\_dns\_name\_verification\_record) | TXT record information for endpoint service private DNS verification |
| <a name="output_relay_inbound_resolver_endpoint_ids"></a> [relay\_inbound\_resolver\_endpoint\_ids](#output\_relay\_inbound\_resolver\_endpoint\_ids) | inbound resolver endpoint ids in relay VPCs |
| <a name="output_relay_inbound_resolver_ips"></a> [relay\_inbound\_resolver\_ips](#output\_relay\_inbound\_resolver\_ips) | fixed inbound resolver IPs in relay VPCs |
| <a name="output_relay_proxy_instance_ids"></a> [relay\_proxy\_instance\_ids](#output\_relay\_proxy\_instance\_ids) | relay proxy instance ids |
| <a name="output_relay_proxy_private_ips"></a> [relay\_proxy\_private\_ips](#output\_relay\_proxy\_private\_ips) | private IP addresses for relay proxy instances |
| <a name="output_relay_vpc_endpoint_dns_entries"></a> [relay\_vpc\_endpoint\_dns\_entries](#output\_relay\_vpc\_endpoint\_dns\_entries) | dns entries for relay interface endpoints |
| <a name="output_relay_vpc_endpoint_ids"></a> [relay\_vpc\_endpoint\_ids](#output\_relay\_vpc\_endpoint\_ids) | interface endpoint ids in relay VPCs |
| <a name="output_service_alb_dns_name"></a> [service\_alb\_dns\_name](#output\_service\_alb\_dns\_name) | DNS name of internal service ALB |
| <a name="output_service_instance_id"></a> [service\_instance\_id](#output\_service\_instance\_id) | primary service web instance id |
| <a name="output_service_instance_ids"></a> [service\_instance\_ids](#output\_service\_instance\_ids) | service web instance ids by AZ role |
| <a name="output_service_nlb_dns_name"></a> [service\_nlb\_dns\_name](#output\_service\_nlb\_dns\_name) | DNS name of service NLB |
| <a name="output_site_to_service_domain"></a> [site\_to\_service\_domain](#output\_site\_to\_service\_domain) | domain name used by site web EC2 to access service through relay proxy |
| <a name="output_site_vpn_router_instance_ids"></a> [site\_vpn\_router\_instance\_ids](#output\_site\_vpn\_router\_instance\_ids) | site vpn router instance ids |
| <a name="output_site_vpn_router_public_ips"></a> [site\_vpn\_router\_public\_ips](#output\_site\_vpn\_router\_public\_ips) | public ips used by customer gateways |
| <a name="output_site_web_instance_ids"></a> [site\_web\_instance\_ids](#output\_site\_web\_instance\_ids) | site web instance ids |
| <a name="output_site_web_private_ip"></a> [site\_web\_private\_ip](#output\_site\_web\_private\_ip) | fixed private IP address used by site web instances |
| <a name="output_transit_gateway_id"></a> [transit\_gateway\_id](#output\_transit\_gateway\_id) | transit gateway id for service-relay connectivity |
| <a name="output_transit_gateway_route_table_ids"></a> [transit\_gateway\_route\_table\_ids](#output\_transit\_gateway\_route\_table\_ids) | transit gateway route table ids |
| <a name="output_vpn_acm_certificate_arn"></a> [vpn\_acm\_certificate\_arn](#output\_vpn\_acm\_certificate\_arn) | ACM certificate ARN for vpn domain |
| <a name="output_vpn_connection_ids"></a> [vpn\_connection\_ids](#output\_vpn\_connection\_ids) | site to relay vpn connection ids |
<!-- END_TF_DOCS -->
