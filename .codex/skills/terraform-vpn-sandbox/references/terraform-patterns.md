# Terraform実装パターン

## 命名
- 単一リソースは`this`を使う。
- 同一タイプを複数作る場合は役割ベースの名前を使う。
- 変数名は文脈を含める（例: `vpc_cidr_block`）。

## ファイル責務
- `main.tf`: 主リソース
- `variables.tf`: 入力変数
- `outputs.tf`: 出力値
- `versions.tf`: Terraform/Provider制約
- `providers.tf`: Provider設定

## リソースブロック順序
1. `count`または`for_each`
2. その他引数
3. `tags`
4. `depends_on`（必要時のみ）
5. `lifecycle`（必要時のみ）

## 変数ブロック順序
1. `description`
2. `type`
3. `default`（必要時のみ）
4. `validation`（必要時のみ）
5. `nullable`（必要時のみ）

## count と for_each の使い分け
- `count`: 真偽値で作成有無を切り替えるとき、固定個数を作るとき。
- `for_each`: 名前付き要素を安定参照したいとき、要素追加・削除の影響を局所化したいとき。

## バージョン方針
- Terraform: `~> 1`
- AWS Provider: `~> 5.0`
- 変更時は`terraform init -upgrade`後に`plan`で差分を必ず確認する。
