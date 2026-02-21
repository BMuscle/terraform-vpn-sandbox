# テストとセキュリティ

## 最低限の検証
```bash
terraform fmt -check -recursive
terraform validate
make plan env=<env>
```

## 追加の静的チェック（任意）
ツールが導入済みの場合のみ実行する。

```bash
tflint
trivy config .
checkov -d .
```

## セキュリティ方針
- 機密情報を変数の平文値で埋め込まない。
- セキュリティグループは最小権限を維持する。
- 暗号化設定を無効化しない。
- 変更後は`plan`で公開範囲の拡大や意図しない削除を重点確認する。

## CI導入時の最小構成
1. `fmt`チェック
2. `validate`
3. `plan`（PR時）
4. `apply`（保護ブランチで承認後）
