# 管理者が一回だけ準備すること

- 組織の GCP プロジェクト `<GCPプロジェクトID>` を開きます。
- OAuth 同意画面の対象を「内部」にします。デスクトップ型 OAuth クライアントを一つ作ります。個人ごとには作りません。
- Gmail、Drive、Sheets、Calendar、Docs、Slides、Apps Script の API を有効にします。
- ダウンロードした `client_secret.json` を 1Password の `Claude-Automation` 保管庫に入れます。項目名は `gws-oauth-client`、欄名は `client_secret.json` にします。公開リポや共有フォルダに置きません。
- Google 管理コンソールの「API の制御」で、この OAuth アプリを許可します。
- 利用者の 1Password の席を追加し、`Claude-Automation` を読めるようにします。
- 利用者に `daimaru-d` の read 権限を付けます。
- 利用者にはセットアップの一行と役割を伝えます。OAuth の同意は各自のブラウザで行います。
