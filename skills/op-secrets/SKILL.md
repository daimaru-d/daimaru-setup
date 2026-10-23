---
name: op-secrets
description: パスワード・ログイン情報・ID・トークン・.env・1Password・金庫・認証情報の話が出たとき、ログインが必要な自動化（AndPad・kintone・各種 Web サービス）を作る／直すとき、.env を作りそうになったときに使う。パスワードを 1Password（大丸開発の金庫）に置き、Claude は値を見ずに「住所」（秘密参照）だけで扱い、実行は op-run.sh 経由にする。
---

# op-secrets — パスワードは 1Password の金庫に、Claude は「住所」だけを扱う

## 1. 何のためのスキルか

- 自動化に使う ID やパスワードを、パソコンの中の平文ファイル（`.env`）ではなく、1Password の金庫（保管庫 `Claude-Automation`）にしまいます。
- Claude Code は値そのものを見ずに、金庫の中の場所を表す「住所」（秘密参照 `op://保管庫/項目/欄`）だけを書きます。
- 実際に動かすときは `op-run.sh` が金庫から値を取り出し、動かすプログラムにだけ渡します。画面に値が出ても伏せ字になります。

## 2. Claude が守ること

- **値を見ない・出さない。** パスワード・トークンを画面に表示する操作（`op read`、`op item get`、`cat .env`、`echo $PASSWORD`、`env` だけの実行など）はしない。見張り（フック）が止めます。
- **`.env` を新しく作らない。** 値が要るときは `.env.op` に住所だけを書く。
- **値が要る処理は必ず `op-run.sh` 経由で動かす。** `op run` を直接組み立てない。
- **パスワードの入力は人に頼む。** ターミナルの表示されない入力欄（`op-item-add.sh` が聞く）か、1Password アプリで入れてもらう。パスワードをコマンドの引数やチャットで受け取らない。もしチャットに貼られたら、使わずに「1Password アプリで入れてください」と伝える。
- **項目名は英小文字・数字・ハイフンだけ**（例: `andpad`、`kintone-keiri`）。日本語や大文字は住所で読めなくなります。
- **保管庫は既定で `Claude-Automation`。** 個人だけで使うものは各自の `Private`（`--vault Private`）。

## 3. 使い方

コマンドは Mac・Windows（Git Bash）共通です。

| やりたいこと | コマンド |
|:--|:--|
| 使える状態か診断する | `bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh` |
| 新しいログイン情報を登録する | `bash ~/.claude/skills/op-secrets/scripts/op-item-add.sh <項目名> --url <URL> --username <ID>` |
| パスワードを自動で作って登録する | `bash ~/.claude/skills/op-secrets/scripts/op-item-add.sh <項目名> --url <URL> --username <ID> --generate` |
| 既存の `.env` を金庫へ移す | `bash ~/.claude/skills/op-secrets/scripts/op-env-migrate.sh <.envの場所>` |
| 自動化を動かす | `bash ~/.claude/skills/op-secrets/scripts/op-run.sh -- <コマンド>` |
| 無人実行の準備（管理者からトークンを受け取った人） | `bash ~/.claude/skills/op-secrets/scripts/op-sa-token.sh set` のあと、`~/.config/daimaru-op/config` の `OP_SA_MODE=1` |
| 無人実行のトークンがあるか確認 | `bash ~/.claude/skills/op-secrets/scripts/op-sa-token.sh status` |

- `op-item-add.sh` は、最後に `.env.op` に貼る行を表示します（例: `ANDPAD_EMAIL=op://Claude-Automation/andpad/username`）。これは住所なので貼っても安全です。
- パスワードを聞かれたとき、Claude が代わりに動かしている場合は入力できないので、空のまま作られます。その場合は人に「1Password アプリで項目を開いてパスワードを入れてください」と頼みます。

## 4. 典型の流れ（AndPad の例）

1. `andpad-browser/.env` に `ANDPAD_EMAIL` と `ANDPAD_PASSWORD` が平文で書かれていた（`op-doctor.sh` の 6 番が知らせる）。
2. 移す: `bash ~/.claude/skills/op-secrets/scripts/op-env-migrate.sh andpad-browser/.env`
   - 金庫に項目 `andpad-browser` ができ、ID とパスワードがそこへ入る。
   - `andpad-browser/.env.op`（住所だけ）と `.env.op.example`（見本）ができ、`.gitignore` に `.env` と `.env.op` が入る。
   - 確認のあと、元の `.env` が消える。
3. 動かす: `cd andpad-browser && bash ~/.claude/skills/op-secrets/scripts/op-run.sh -- node create-mitsumori-draft.mjs`
   - `dotenv` を使うコードも、`.env` が無くなっても `op run` が渡す環境変数でそのまま動きます。

## 5. うまくいかないとき

まず `bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh` を実行し、✗ の番号を見ます。

| 番号 | 意味 | 対処 |
|:--|:--|:--|
| 1 | 1Password CLI（op）が無い | Mac: `brew install 1password-cli`／Windows: `winget install AgileBits.1Password.CLI`（入れた後 Git Bash を開き直す） |
| 2 | サインインできていない | 1Password アプリでサインイン → 設定 → 開発者 → 「1Password CLI と連携」を ON → `op signin --account daimaruenterprise.1password.com` |
| 3 | アカウントが op に登録されていない | 2 と同じ手順で `daimaruenterprise.1password.com` にサインイン |
| 4 | 保管庫 `Claude-Automation` が見えない | 1Password の管理者に保管庫の共有を依頼 |
| 5 | Claude Code の見張り・禁止リストが無い | `bash ~/.claude/skills/op-secrets/scripts/install.sh` をもう一度 |
| 6 | 平文の `.env` がある（注意） | 表示された `op-env-migrate.sh` のコマンドで移す |
| 7 | 無人実行なのにトークンが無い | `op-sa-token.sh set`（トークンは管理者から受け取る） |

- Windows では Claude Code の Bash は Git Bash です。コマンドはこの資料のまま動きます。組織の設定で `claude` が動かない PC は `claude.cmd` で起動します。
- 「invalid character in secret reference」と出たら、項目名か保管庫名に日本語・空白が入っています。英小文字・数字・ハイフンの名前で作り直します。

## 6. 管理者向けの一言

保管庫 `Claude-Automation` の作成と共有、無人実行用のサービスアカウントの発行は、1Password の管理者が行います。詳しくは daimaru-setup の `docs/op-secrets_運用ガイド.md`（https://github.com/daimaru-d/daimaru-setup/blob/main/docs/op-secrets_運用ガイド.md）を見てください。
