# daimaru-setup — 大丸 業務ハブのかんたん初期セットアップ（Windows）

大丸の業務ハブ [daimaru-skills](https://github.com/daimaru-d/daimaru-skills) を、
**むずかしい設定なしで** Windows パソコンに用意するためのスクリプトです。

## 使い方（コピペ1行）

1. スタートメニューで `PowerShell` と打って **Windows PowerShell** を開く
2. 次の1行を貼り付けて Enter：

```powershell
irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.ps1 | iex
```

3. 途中でブラウザが開いたら、**許可された GitHub アカウント**でログインしてください
4. 最後に Claude Code が起動します。`/setup` と打てば全業務の中身がそろいます

## このスクリプトがやること

| 手順 | 内容 |
|:--|:--|
| 1 | Git / Node.js / GitHub CLI を導入（winget） |
| 2 | Claude Code を導入（npm） |
| 3 | GitHub にブラウザでログイン |
| 4 | 業務ハブ `daimaru-skills` を取り込み、Claude Code を起動 |

> 取り込みに失敗する場合、ほとんどは「対象リポジトリの閲覧権限が無い」だけです。
> その場合は管理者に read 権限の付与を依頼してください。

## 安全性について

- このスクリプトは公開されており、中身（[setup.ps1](./setup.ps1)）は誰でも確認できます。
- パスワードやトークンは一切含みません。GitHub ログインは公式のブラウザ認証のみを使います。
