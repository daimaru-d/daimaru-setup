# daimaru-setup — 大丸 業務ハブのかんたん初期セットアップ

大丸の業務ハブ [daimaru-skills](https://github.com/daimaru-d/daimaru-skills) を、
**むずかしい設定なしで** パソコンに用意するためのスクリプトです（macOS / Linux / Windows 対応）。

## 使い方（コピペ1行）

ターミナルに**下の1行を貼って Enter**するだけ。途中ブラウザが開いたら、案内されたアカウントでログインしてください。

| OS | 開くもの | 貼る1行 |
|:--|:--|:--|
| **macOS / Linux** | ターミナル | `curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.sh \| bash` |
| **Windows** | Windows PowerShell | `irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.ps1 \| iex` |

最後に Claude Code が**安全バイパス**（プロンプト最小・破壊操作はブロック）で起動します。
起動後の流れ: `bash .claude/skills/bi-dashboard/harness/bi-doctor.sh`（自己診断）→ `/bi-coach`（ダッシュボード作成）。

## このスクリプトがやること

| 手順 | 内容 |
|:--|:--|
| 1 | **Claude Code** を導入（公式インストーラ。Win は npm） |
| 2 | 開発ツールを導入: Git / Node.js / gh / **gcloud / clasp / cloud-sql-proxy** |
| 3 | GitHub にブラウザでログイン |
| 4 | 業務ハブ `daimaru-skills` を取り込み（`npm ci` 含む） |
| 5 | BI用ログイン: gcloud / **ADC(`application-default`)** / clasp → 安全バイパスで Claude 起動 |
| 6 | **パスワード金庫（1Password）**: 1Password CLI を導入し、Claude Code にスキル `op-secrets`（見張りつき）を入れる |

> `cloud-sql-proxy` は `gcloud components install cloud-sql-proxy` で導入（手動DL不要・自動でPATH）。
> ブラウザ認証（GitHub / Google / ADC / clasp）は途中で開くので、各自ログインしてください。

> 取り込みに失敗する場合、ほとんどは「対象リポジトリの閲覧権限が無い」だけです。
> その場合は管理者に `daimaru-d` への read 権限の付与を依頼してください。

## うまくいかないとき

- **macOS で Homebrew が無い**: 一部の自動導入がスキップされます。https://brew.sh で Homebrew を入れてからもう一度実行すると楽です。
- **Windows「スクリプトの実行が無効（running scripts is disabled / PSSecurityException）」**
  → このスクリプトは `.cmd` 版を直接呼ぶよう対策済みです。**もう一度この1行を実行**してください（入ったソフトは自動スキップ）。
  組織ポリシーで制限された PC では、**次回からの起動は `claude` ではなく `claude.cmd`** と打ってください。
- **詰まったら**: Claude 起動後に `bash .claude/skills/bi-dashboard/harness/bi-doctor.sh` を実行すると、不足が OS別の直し方付きで一覧表示されます。

## 安全性について

- このスクリプトは公開されており、中身（[setup.sh](./setup.sh) / [setup.ps1](./setup.ps1)）は誰でも確認できます。
- パスワードやトークンは一切含みません。ログインは公式のブラウザ認証のみを使います。
- 起動する Claude Code は **安全バイパス**設定（`daimaru-skills/.claude/settings.json` の allow/deny）。定型コマンドは聞かれず、`rm -rf`・`git push`・`.env`編集 などの破壊的操作はブロックされます。

## 総務経理部門向け（納付期限の見張り・返済期日アラート）

総務経理の自動化リポジトリ `daimaru-keiri-automation` を導入する場合は、上の1行ではなく**こちら**を貼ってください
（Claude Code / Git / GitHub CLI / Node / Python / VS Code(日本語化) と Playwright を入れ、リポジトリを取り込んで VS Code で開きます）。

| OS | 開くもの | 貼る1行 |
|:--|:--|:--|
| **Windows** | Windows PowerShell | `irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/keiri/onboard.ps1 \| iex` |
| **macOS** | ターミナル | `curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/keiri/onboard.sh \| bash` |

- 途中でブラウザが2回開きます（GitHub と Claude のログイン）。それ以外はほぼ待ち時間です（15〜25分）。
- `daimaru-keiri-automation` は非公開リポジトリです。取り込みに失敗する場合は GitHub のユーザー名を GScale までお知らせください（招待します）。
- つまずいたら `%USERPROFILE%\gscale-onboard.log`（Mac は `~/gscale-onboard.log`）を送ってください。
- `scripts/keiri/` のファイルは GScale-jp/fde-setup から自動生成されています。直接編集しないでください。

## パスワードを 1Password で管理する（op-secrets）

自動化に使う ID・パスワードを、平文の `.env` ではなく 1Password（`daimaruenterprise.1password.com` の保管庫 `Claude-Automation`）に置き、
Claude Code が**値を見ずに**使えるようにするスキルです。上の1行（本体のセットアップ）に含まれていますが、既に導入済みの人は次の1行だけで入れられます。

| OS | 開くもの | 貼る1行 |
|:--|:--|:--|
| **macOS / Linux** | ターミナル | `curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/setup.sh \| bash` |
| **Windows** | Windows PowerShell | `irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/setup.ps1 \| iex` |

- 1Password アプリ側で、サインインと「設定 → 開発者 → 1Password CLI と連携」を ON にしてください（最初の1回だけ）。
- 診断: `bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh`（最後の行が `OP_DOCTOR: PASS` なら準備完了）
- 動かし方: `.env.op` に「住所」（`op://Claude-Automation/項目/欄`）だけを書き、`bash ~/.claude/skills/op-secrets/scripts/op-run.sh -- <コマンド>` で動かします。
  既存の `.env` は `op-env-migrate.sh <.envの場所>` で移せます。詳しくは [skills/op-secrets/SKILL.md](./skills/op-secrets/SKILL.md) と [運用ガイド](./docs/op-secrets_運用ガイド.md)。
- Claude Code の設定（`~/.claude/settings.json`）に、値を画面に出すコマンド（1Password の値の表示や `.env` の表示など）を止める見張りが入ります。
- 無人実行のトークン（1Password のサービスアカウント）は、管理者が対象の PC で入れます: Windows は PowerShell で `irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/sa-token.ps1 | iex`、Mac はターミナルで `curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/sa-token.sh | bash`（トークンは表示されません）。

開発者向けのテスト: `bash tests/scripts.test.sh && node --test tests/*.test.js`
