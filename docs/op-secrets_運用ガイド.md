# Claude Code で使うパスワードを 1Password で管理する運用ガイド

この資料について
- 何の資料か：Claude Code で使うパスワードを 1Password で管理するしくみの運用ガイド
- 結論：パスワードは `.env` に書かず、1Password の共有保管庫 `Claude-Automation`（個人用は `Private`）に置き、Claude Code は値を見ずに使う
- お願いしたいこと：管理者は保管庫の作成と権限付与を、利用者は 1Password アプリの CLI 連携を ON にしてワンライナーを実行し、診断が PASS になるまで直す


## 1. しくみ

パスワードは 1Password の共有保管庫 `Claude-Automation` に置きます（自分だけが使うものは各自の `Private` に）。Claude Code は必要なときだけ 1Password から受け取って使い、画面には出しません。`.env` にパスワードを書く運用はやめます。`.env` の代わりに、値を含まない `.env.op` というファイルを Claude Code が作ります（中身は 1Password のどこにあるかを示す住所だけ）。

## 2. 利用者がやること

### 初回だけ、自分でやること（3つ）

1. 1Password アプリにサインインする。
2. アプリの「設定 → 開発者 → 1Password CLI と連携」を ON にする。
3. ワンライナー（1行貼るだけのセットアップ用コマンド。1Password の道具を入れ、Claude Code にこの金庫の使い方と、値を画面に出さない設定を入れる）を、Windows なら PowerShell、Mac ならターミナルに貼る。

ワンライナーの中身は大丸開発の GitHub（daimaru-d）に公開されていて、誰でも確認できます。

Windows（PowerShell）:

```powershell
irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/setup.ps1 | iex
```

Mac（ターミナル）:

```bash
curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/setup.sh | bash
```

### ふだんは、Claude Code に話しかけるだけ

以後は Windows でも Mac でも、Claude Code に次の言葉で頼めば、Claude Code が必要なコマンドを実行します。自分でコマンドを打つことはありません。

| 頼む言葉 | できること |
| :--- | :--- |
| 「パスワードの金庫を診断して」 | 1Password の道具・アプリとの連携・保管庫が見えるか・古い `.env` が残っていないかを調べ、足りない所の直し方を出す。最終行が `OP_DOCTOR: PASS` になるまで直す。 |
| 「この `.env` を 1Password に移して」 | 1Password に項目を作り、`.env.op` を作り、確認してから元の `.env` を消す。既にある `.env` は、次にその業務を Claude Code で動かすときに移す。 |
| 「AndPad のログイン情報を登録して」 | 項目の名前は英小文字・数字・ハイフンだけ（例 `andpad`）。パスワードはその場で非表示入力するか、空のまま作って 1Password アプリで入れる。 |
| 「AndPad の下書き作成を動かして」 | 動いている間だけ値が渡り、画面には出ない。 |

Windows では Claude Code が内蔵の bash で実行するので、PowerShell で打ち直す必要はありません。

## 3. 管理者がやること

### 全員に必要

保管庫 `Claude-Automation` を作り、使う人に閲覧（読み取り）権限を付ける。自分でログイン情報を登録する人には「項目の作成」も許可する。

退職・異動のときは、管理者が次の3つを行う: 保管庫の権限を外す／サービスアカウントを無効にする（無人で動かす PC がある場合だけ）／その人が使っていた共有のパスワードを変える。

### 無人で動かす PC がある場合だけ

夜間や早朝に人がいなくても自動で動かす PC が該当します。該当するかは GScale と相談してください。

サービスアカウント（人のアカウントと違い、ログインの画面がなく、共有保管庫 `Claude-Automation` だけを読める専用アカウント）を、1Password の管理画面で発行する。発行時に一度だけ表示されるトークン（パスワードの代わりになる長い文字列）は、チャットやメールで送らない。対象 PC で、PowerShell（Mac はターミナル）に次の1行を貼ると、表示されない入力欄が出るので、そこにトークンを貼る。

Windows（PowerShell）:

```powershell
irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/sa-token.ps1 | iex
```

Mac（ターミナル）:

```bash
curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/sa-token.sh | bash
```

最後に、同じ PC の Claude Code に「この PC を無人実行に切り替えて」と頼む。

## 4. 入れてよいもの・入れないもの

入れてよいものは、AndPad、kintone、各種 Web サービスのログイン情報、API トークンです。

銀行の取引承認や振込のパスワードは入れないでください（お金が動く承認は人が行うためです）。Google アカウントのパスワードも入れません。Google のログインは自動化できないため、これまでどおりブラウザで行います。

## 5. 困ったとき

診断で足りない所と直し方が出ます。多いのは「1Password の道具が入っていない」「CLI 連携が OFF」「保管庫が見えない（管理者に共有を依頼）」の3つです。

Windows（PowerShell）:

```powershell
winget install AgileBits.1Password.CLI
```

Mac（ターミナル）:

```bash
brew install 1password-cli
```

## 6. 相談先

GScale（神谷）。Slack の `#prj-daimaru-gscale` に書いてください。

## 付録: Claude Code が実行するコマンド（情報システム担当向け）

次の表は、利用者が Claude Code に頼んだときに Claude Code が実行するコマンドです。

| 頼む言葉 | 実行するコマンド |
| :--- | :--- |
| 「パスワードの金庫を診断して」 | `bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh` |
| 「この `.env` を 1Password に移して」 | `bash ~/.claude/skills/op-secrets/scripts/op-env-migrate.sh <.env のパス>` |
| 「AndPad のログイン情報を登録して」 | `bash ~/.claude/skills/op-secrets/scripts/op-item-add.sh <項目名> --url <URL> --username <ID>` |
| 「AndPad の下書き作成を動かして」 | `bash ~/.claude/skills/op-secrets/scripts/op-run.sh -- <コマンド>` |
| トークン登録 | Windows（PowerShell）: `irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/sa-token.ps1 \| iex` ／ Mac（ターミナル）: `curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/sa-token.sh \| bash` |
| 「この PC を無人実行に切り替えて」 | 設定ファイル `~/.config/daimaru-op/config` に `OP_SA_MODE=1` を書く |
