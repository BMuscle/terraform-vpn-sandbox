# AGENTS.md

このファイルは、`terraform-vpn-sandbox` リポジトリで作業するエージェント向けの運用ガイドです。

## プロジェクト概要

- 目的: 拠点間VPNを使ったマルチテナント提供構成の検証
- 前提: 単一AZ (`ap-northeast-1a`)
- 現在の主要構成:
  - サービスVPC: `10.0.0.0/24`
  - 中継VPC-A: `10.0.10.0/27`
  - 中継VPC-B: `10.0.10.32/27`
  - 拠点VPC-A/B: `192.168.10.0/24`（重複）

## 会話と編集ルール

- 常に日本語で回答する。
- 指示がない限り、UTF-8で編集する。
- 複雑な処理には日本語コメントを付ける。
- 自明なコメントは書かない。
- 不要な空白は入れない。
- 新規ファイルは末尾改行を入れる。

## Git運用ルール

- `git commit` / `git push` は `/commit-push` 指示時のみ実行する。
- ユーザーが「コミットして」「プッシュして」と言った場合は、`/commit-push` を案内する。
- ステージングは個別ファイル指定で行う（`git add .` / `git add -A` は使わない）。
- コミットメッセージは Conventional Commits 形式に従う。

## Terraform運用フロー

1. `terraform fmt -check -recursive`
2. `make plan env=<env>`
3. 承認後 `make apply env=<env>`

補足:
- `Makefile` の `init` は `backends/<env>.tfbackend` を参照する。
- `vars/<env>.tfvars` の `aws_account_id`, `name`, `env` を事前に確認する。

## 実装済みの重要前提

- PrivateLink:
  - サービスVPC側に `NLB + Endpoint Service`
  - 中継VPC側に Interface VPC Endpoint
  - 固定IP:
    - relay_a: `10.0.10.4`
    - relay_b: `10.0.10.36`
  - `aws_vpc_endpoint.relay` は `subnet_configuration` と `subnet_ids` を併記する。

- VPN:
  - 中継VPCにVGW、拠点側はCGW（VPNルータEC2のEIP）
  - 拠点CIDR重複のため `static_routes_only=true`
  - 拠点EC2 -> サービス疎通のため、VPNルータSGで転送トラフィックを許可する。

- DNS:
  - 拠点VPC（`site_a`, `site_b`）はオンプレ相当として
    - `enable_dns_support=false`
    - `enable_dns_hostnames=false`

## 手動構築の前提

- Webサーバー:
  - Amazon Linux 2023 に `nginx` を手動インストール
- VPNルーター:
  - Amazon Linux 2023 に `libreswan` を手動設定
  - `modp1024` は不可。`modp2048` を使用
  - 状態確認は `ipsec status` / `ipsec trafficstatus`

## 変更時の確認観点

- 拠点A/B間に通信経路を作っていないこと。
- サービス公開がインターネット向けになっていないこと。
- SGに不要な `0.0.0.0/0` 受信許可が増えていないこと。
- ルートが「拠点 -> 中継 -> サービス」以外へ漏れていないこと。

## 参照ファイル

- `README.md`: 手動手順と構成説明
- `network.tf`: VPC/Subnet/Route
- `security.tf`: SG方針
- `privatelink.tf`: NLB/Endpoint Service/VPCE
- `vpn.tf`: VGW/CGW/VPN connection/route
