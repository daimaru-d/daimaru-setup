# daimaru-setup

## 1行貼るだけで仕事の道具がそろいます

下の1行を貼り付けて Enter を押すと、仕事に必要な道具が一度にそろいます。同じ操作をもう一度しても壊れることはなく、足りない所だけが直ります。途中でブラウザが開いたら、画面の案内どおりにログインしてください。

| OS | 実行する一行 |
|:--|:--|
| macOS / Linux | `curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.sh \| bash` |
| Windows PowerShell | `irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.ps1 \| iex` |

## 自分の役割を選ぶ

役割は、設計（sekkei）、統合ダッシュボード（togo）、用地（yochi）、総務経理（somu-keiri）、基本（base）の5つです。実行する前に、DAIMARU_ROLE という設定で自分の役割を指定します。役割が決まっていなければ基本（base）のまま進めてよく、決まったあとで役割を指定してもう一度実行すれば足ります。

| 値 | 準備する主なもの |
|:--|:--|
| `base` | Git、Node.js、GitHub CLI、Claude Code |
| `sekkei` | 共通の道具、VS Code、gws、Chrome と拡張の案内 |
| `togo` | 共通の道具、gws、clasp、gcloud、ADC |
| `yochi` | 共通の道具、gws（Gmail、Drive） |
| `somu-keiri` | 共通の道具、gws、1Password、[経理の追加手順](./scripts/keiri/) |

例: macOS / Linux は `curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.sh | DAIMARU_ROLE=sekkei bash`、Windows は `$env:DAIMARU_ROLE='sekkei'; irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.ps1 | iex` を実行します。役割を指定しなければ対話端末から選べます。

## うまくいっているか確かめる

doctor という診断を実行すると、できていない所とその直し方が1行ずつ表示されます。最後の行が DAIMARU_DOCTOR: PASS なら準備は完了です。FAIL と出た場合は、表示された行をそのまま管理者に伝えてください。
| 操作 | macOS / Linux | Windows PowerShell |
|:--|:--|:--|
| 予定だけ表示 | `DAIMARU_DRY_RUN=1 DAIMARU_ROLE=sekkei bash setup.sh` | `$env:DAIMARU_DRY_RUN='1'; .\setup.ps1` |
| 更新 | `DAIMARU_UPDATE=1 bash setup.sh` | `$env:DAIMARU_UPDATE='1'; .\setup.ps1` |
| 診断 | `curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/doctor/doctor.sh \| bash` | `irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/doctor/doctor.ps1 \| iex` |
| 通信せず診断 | `DAIMARU_DOCTOR_SKIP_NETWORK=1 bash doctor/doctor.sh` | `$env:DAIMARU_DOCTOR_SKIP_NETWORK='1'; .\doctor\doctor.ps1` |

共有 OAuth 設定が読めない場合は、管理者に 1Password の招待を頼んでください。

管理者向け: [一回だけの準備](./docs/admin_一回だけの準備.md)。1Password の詳しい使い方は [運用ガイド](./docs/op-secrets_運用ガイド.md)。

開発テスト: `bash tests/scripts.test.sh && bash tests/kitting.test.sh && node --test tests/op-guard.test.js`

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
