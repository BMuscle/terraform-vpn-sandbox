# terraform-vpn-sandbox

## 概要

拠点間VPNを使ったマルチテナント提供モデルを検証するためのTerraformです。

- 単一AZ: `ap-northeast-1a`
- サービス側: サービスVPC 1つ + 中継VPC 2つ
- 拠点側: 拠点VPC 2つ（CIDR重複）
- 拠点 -> 中継: Site-to-Site VPN（中継VGW、拠点CGW）
- 中継 -> サービス: PrivateLink（NLB + Endpoint Service + Interface Endpoint）

## ネットワーク構成

- サービスVPC: `10.0.0.0/24`
- 中継VPC-A: `10.0.10.0/27`
- 中継VPC-B: `10.0.10.32/27`
- 拠点VPC-A/B（重複）: `192.168.10.0/24`
- 固定Endpoint IP:
  - 中継A: `10.0.10.4`
  - 中継B: `10.0.10.36`

## 構築対象

- Amazon Linux 2023 + `t4g.nano` + `gp3 10GB` のEC2（サービス/拠点/拠点VPNルータ）
- サービスVPC内のInternal NLB（TCP/80）
- PrivateLink Endpoint Service
- 中継VPC内のInterface VPC Endpoint（固定IP指定）
- 中継VPCごとのVGW
- 拠点ごとのCGW（拠点VPNルータEC2のEIPを利用）
- 拠点ごとのSite-to-Site VPN接続
- EC2 Instance Connect Endpoint（サービスVPC/拠点VPC）

## 手動作業

- Nginxのインストール/設定は手動
- 拠点VPNルータ（Libreswan等）の設定は手動

## Nginx設定手順（WebサーバーEC2へSSH接続後）

この手順はサービスVPCのWeb EC2、拠点VPCのWeb EC2のどちらでも同じです。

1. Nginxをインストール

```bash
sudo dnf install -y nginx
```

2. Nginxを起動し、自動起動を有効化

```bash
sudo systemctl enable --now nginx
sudo systemctl status nginx --no-pager
```

3. ローカル確認（EC2自身で80番応答を確認）

```bash
curl -I http://127.0.0.1
```

`HTTP/1.1 200 OK` が返れば、デフォルトページ配信まで完了です。

4. リモート疎通確認

```bash
# site_a拠点から service への確認
curl -I http://10.0.10.4

# site_b拠点から service への確認
curl -I http://10.0.10.36
```

補足:
- サービスWeb EC2はインターネットからの直接到達を許可していません。
- 拠点Web EC2のHTTPは同一拠点CIDR（`192.168.10.0/24`）からのみ許可しています。

## Libreswan設定手順（拠点VPNルータへSSH接続後）

この手順は `site_a` / `site_b` のVPNルータEC2でそれぞれ実施します。
`site_a` は中継CIDRに `10.0.10.0/27`、`site_b` は `10.0.10.32/27` を使ってください。

事前に AWS コンソールの `VPN Connections` から対象接続の `Download configuration` を取得し、以下の値を控えておきます。

- トンネル1 Outside IP
- トンネル2 Outside IP
- 各トンネルの Pre-Shared Key
- 拠点VPNルータEC2のEIP（CGWとして登録済みのIP）

1. 変数を設定

```bash
SITE_EIP="<拠点VPNルータのEIP>"
SITE_SUBNET="192.168.10.0/24"
RELAY_SUBNET="<site_aなら10.0.10.0/27、site_bなら10.0.10.32/27>"
TUNNEL1_OUTSIDE_IP="<Tunnel1のOutside IP>"
TUNNEL2_OUTSIDE_IP="<Tunnel2のOutside IP>"
PSK1="<Tunnel1のPSK>"
PSK2="<Tunnel2のPSK>"
```

2. Libreswanをインストール

```bash
sudo dnf install -y libreswan
```

3. IPフォワーディングを有効化

```bash
sudo tee /etc/sysctl.d/99-vpn-router.conf >/dev/null <<EOF
net.ipv4.ip_forward=1
EOF
sudo sysctl --system
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
  rightsubnet=${RELAY_SUBNET}
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
# site_a側の確認
curl -I http://10.0.10.4

# site_b側の確認
curl -I http://10.0.10.36
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
| [aws_customer_gateway.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/customer_gateway) | resource |
| [aws_ec2_instance_connect_endpoint.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_instance_connect_endpoint) | resource |
| [aws_eip.site_vpn_router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_instance.service_web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_instance.site_vpn_router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_instance.site_web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_lb.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.service_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_route.default_to_igw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.relay_to_site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.site_to_relay](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.eic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.relay_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.service_web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.site_vpn_router](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.site_web](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.relay](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint_service.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint_service) | resource |
| [aws_vpc_endpoint_service_allowed_principal.same_account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint_service_allowed_principal) | resource |
| [aws_vpn_connection.site_to_relay](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection) | resource |
| [aws_vpn_connection_route.site_network](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection_route) | resource |
| [aws_vpn_gateway.relay](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway) | resource |
| [aws_ami.amazon_linux_arm64](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account id | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region | `string` | `"ap-northeast-1"` | no |
| <a name="input_az"></a> [az](#input\_az) | single availability zone | `string` | `"ap-northeast-1a"` | no |
| <a name="input_endpoint_private_ips"></a> [endpoint\_private\_ips](#input\_endpoint\_private\_ips) | fixed private IP addresses for relay interface endpoints | `map(string)` | <pre>{<br>  "relay_a": "10.0.10.4",<br>  "relay_b": "10.0.10.36"<br>}</pre> | no |
| <a name="input_env"></a> [env](#input\_env) | environment name | `string` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | ec2 instance type for web and vpn instances | `string` | `"t4g.nano"` | no |
| <a name="input_name"></a> [name](#input\_name) | resource name prefix | `string` | n/a | yes |
| <a name="input_relay_vgw_asns"></a> [relay\_vgw\_asns](#input\_relay\_vgw\_asns) | amazon side ASN for relay VGWs | `map(number)` | <pre>{<br>  "relay_a": 64512,<br>  "relay_b": 64513<br>}</pre> | no |
| <a name="input_relay_vpc_cidrs"></a> [relay\_vpc\_cidrs](#input\_relay\_vpc\_cidrs) | relay vpc cidr blocks | `map(string)` | <pre>{<br>  "relay_a": "10.0.10.0/27",<br>  "relay_b": "10.0.10.32/27"<br>}</pre> | no |
| <a name="input_root_volume_size_gb"></a> [root\_volume\_size\_gb](#input\_root\_volume\_size\_gb) | root ebs volume size in GB | `number` | `10` | no |
| <a name="input_service_vpc_cidr"></a> [service\_vpc\_cidr](#input\_service\_vpc\_cidr) | service vpc cidr block | `string` | `"10.0.0.0/24"` | no |
| <a name="input_site_customer_gateway_bgp_asns"></a> [site\_customer\_gateway\_bgp\_asns](#input\_site\_customer\_gateway\_bgp\_asns) | BGP ASNs for site customer gateways | `map(number)` | <pre>{<br>  "site_a": 65010,<br>  "site_b": 65020<br>}</pre> | no |
| <a name="input_site_vpc_cidr"></a> [site\_vpc\_cidr](#input\_site\_vpc\_cidr) | site vpc cidr block | `string` | `"192.168.10.0/24"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | default tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ec2_instance_connect_endpoint_ids"></a> [ec2\_instance\_connect\_endpoint\_ids](#output\_ec2\_instance\_connect\_endpoint\_ids) | EC2 Instance Connect Endpoint ids |
| <a name="output_relay_vpc_endpoint_fixed_ips"></a> [relay\_vpc\_endpoint\_fixed\_ips](#output\_relay\_vpc\_endpoint\_fixed\_ips) | fixed private IP addresses for relay interface endpoints |
| <a name="output_relay_vpc_endpoint_ids"></a> [relay\_vpc\_endpoint\_ids](#output\_relay\_vpc\_endpoint\_ids) | interface endpoint ids in relay VPCs |
| <a name="output_service_instance_id"></a> [service\_instance\_id](#output\_service\_instance\_id) | service web instance id |
| <a name="output_service_nlb_dns_name"></a> [service\_nlb\_dns\_name](#output\_service\_nlb\_dns\_name) | DNS name of service NLB |
| <a name="output_site_vpn_router_instance_ids"></a> [site\_vpn\_router\_instance\_ids](#output\_site\_vpn\_router\_instance\_ids) | site vpn router instance ids |
| <a name="output_site_vpn_router_public_ips"></a> [site\_vpn\_router\_public\_ips](#output\_site\_vpn\_router\_public\_ips) | public ips used by customer gateways |
| <a name="output_site_web_instance_ids"></a> [site\_web\_instance\_ids](#output\_site\_web\_instance\_ids) | site web instance ids |
| <a name="output_vpn_connection_ids"></a> [vpn\_connection\_ids](#output\_vpn\_connection\_ids) | site to relay vpn connection ids |
<!-- END_TF_DOCS -->
