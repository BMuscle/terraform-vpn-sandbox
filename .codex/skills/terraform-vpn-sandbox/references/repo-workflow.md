# リポジトリ運用

## 前提
- このリポジトリは`Makefile`経由の実行を標準とする。
- 環境名は`env`で指定し、`vars/<env>.tfvars`を使う。
- stateは`make init env=<env>`の内部で`states/<env>.tfstate`に向く。

## 基本コマンド
```bash
make plan env=dev
make apply env=dev
```

## 実行順序
1. `make plan env=<env>`を実行する。
2. 差分と影響範囲を確認する。
3. 承認後に`make apply env=<env>`を実行する。

## Makefileに沿った補足
- `make plan`と`make apply`は内部で`init`と`validate`を実行する。
- `fmt`は`terraform fmt -check -recursive`を実行する。
- `aws_account_id`や`env`の未設定は`variables.tf`と`.tfvars`を確認する。
