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

例: macOS / Linux は `DAIMARU_ROLE=sekkei` を設定してから一行を実行します。Windows は `$env:DAIMARU_ROLE='sekkei'` を設定します。対話実行では役割を選べます。

## うまくいっているか確かめる

doctor という診断を実行すると、できていない所とその直し方が1行ずつ表示されます。最後の行が DAIMARU_DOCTOR: PASS なら準備は完了です。FAIL と出た場合は、表示された行をそのまま管理者に伝えてください。
| 操作 | macOS / Linux | Windows PowerShell |
|:--|:--|:--|
| 予定だけ表示 | `DAIMARU_DRY_RUN=1 DAIMARU_ROLE=sekkei bash setup.sh` | `$env:DAIMARU_DRY_RUN='1'; .\setup.ps1` |
| 更新 | `DAIMARU_UPDATE=1 bash setup.sh` | `$env:DAIMARU_UPDATE='1'; .\setup.ps1` |
| 診断 | `bash doctor/doctor.sh` | `.\doctor\doctor.ps1` |
| 通信せず診断 | `DAIMARU_DOCTOR_SKIP_NETWORK=1 bash doctor/doctor.sh` | `$env:DAIMARU_DOCTOR_SKIP_NETWORK='1'; .\doctor\doctor.ps1` |

共有 OAuth 設定が読めない場合は、管理者に 1Password の招待を頼んでください。

管理者向け: [一回だけの準備](./docs/admin_一回だけの準備.md)。1Password の詳しい使い方は [運用ガイド](./docs/op-secrets_運用ガイド.md)。

開発テスト: `bash tests/scripts.test.sh && bash tests/kitting.test.sh && node --test tests/op-guard.test.js`
