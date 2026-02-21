---
name: terraform-vpn-sandbox
description: terraform-vpn-sandboxリポジトリのTerraformコードを追加・変更・レビューするときに使う。`make plan env=...`と`make apply env=...`の運用を前提に、変数定義、タグ設計、命名、count/for_eachの選択、fmt/validate/planの検証フローを統一する。AWS向けVPN検証環境の安全なIaC運用に適用する。
---
# Terraform VPN Sandboxスキル

## 実行原則
- 既存の`Makefile`タスクを優先して実行する。
- 変更前に`terraform fmt -check -recursive`と`terraform validate`が通る状態を保つ。
- 変更後は必ず`make plan env=<env>`で差分確認してから`apply`を検討する。
- リポジトリ固有の運用を優先し、一般論の導入は必要最小限にする。

## 標準ワークフロー
1. 対象環境を決め、`vars/<env>.tfvars`の存在を確認する。
2. 変更箇所と依存関係を把握する（`variables.tf`、`providers.tf`、`versions.tf`、対象`.tf`）。
3. Terraformコードを修正する。
4. `make plan env=<env>`で`init`+`validate`+`plan`を実行する。
5. 承認後に`make apply env=<env>`を実行する。
6. 変更内容と影響範囲を要約し、未実施の検証があれば明示する。

## 実装規約
- 変数には`description`と`type`を必ず付ける。
- 複数作るリソースは役割名で命名する。単一リソースのみ`this`を許可する。
- `count`は単純なON/OFFや固定数に限定し、要素の増減やキー参照が必要なら`for_each`を使う。
- リソースブロックは`count/for_each`を先頭、`tags`を末尾寄りに置き、`lifecycle`は最後に置く。
- タグは`local.tags`の統一方針を壊さず、環境情報（`var.env`）を維持する。

## 参照ファイル
- 日常運用と`Makefile`前提は`references/repo-workflow.md`を読む。
- 命名規約や`count/for_each`の判断は`references/terraform-patterns.md`を読む。
- テスト・セキュリティチェック導入は`references/testing-and-security.md`を読む。

## 非対象
- Terraformコード変更を伴わないクラウド一般論のみの相談。
