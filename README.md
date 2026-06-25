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
