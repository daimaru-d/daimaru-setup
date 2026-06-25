# ============================================================
# 大丸 業務ハブ（daimaru-skills）初期セットアップ - Windows用
# 使い方: PowerShell に次の1行を貼って Enter するだけ
#   irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.ps1 | iex
# ============================================================
# gh / git / npm などの外部コマンドは標準エラーへ進捗や通知を書く。
# "Stop" だとそれだけで NativeCommandError になり途中で止まるため "Continue" にする。
# 重要な工程は後段で終了コード($LASTEXITCODE)を見て個別に判定する。
$ErrorActionPreference = "Continue"

# --- 実行ポリシー対策 ---
# Windows では npm / claude の実体が .ps1（PowerShellスクリプト）のため、
# 「スクリプトの実行が無効」だと npm.ps1 が読めずに失敗する。
# (1) 可能なら本人スコープを RemoteSigned にして今後も .ps1 を使えるようにする（管理者不要）
# (2) 組織ポリシーで変更できない場合に備え、このスクリプト内では .cmd 版を直接呼ぶ
$script:PolicyOk = $true
try {
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
} catch {
  $script:PolicyOk = $false
  Write-Host "  （実行ポリシーは組織設定のため変更できませんでした。.cmd 経由で続行します）" -ForegroundColor DarkYellow
}
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

# winget でソフトを入れた直後は PATH が未反映になるため、都度読み直す
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
              [Environment]::GetEnvironmentVariable("Path","User")
}
# .ps1 を避けて .cmd / .exe の実体を探して呼ぶ（実行ポリシーに左右されない）
function Invoke-Cli {
  param([string]$Name, [string[]]$CliArgs)
  $cmd = (Get-Command "$Name.cmd","$Name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1)
  if (-not $cmd) { $cmd = Get-Command $Name -ErrorAction Stop }
  & $cmd.Source @CliArgs
}

Write-Host ""
Write-Host "==> 1/4 必要なソフトを入れています (Git / Node.js / GitHub CLI)" -ForegroundColor Cyan
winget install --id Git.Git           -e --accept-package-agreements --accept-source-agreements
winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
winget install --id GitHub.cli        -e --accept-package-agreements --accept-source-agreements
Refresh-Path

Write-Host ""
Write-Host "==> 2/4 Claude Code を入れています" -ForegroundColor Cyan
# npm.ps1 ではなく npm.cmd を直接呼ぶ（スクリプト実行が無効でも動く）
Invoke-Cli npm @("install","-g","@anthropic-ai/claude-code")
Refresh-Path
if (-not (Get-Command claude.cmd,claude.exe,claude -ErrorAction SilentlyContinue)) {
  Write-Host "  ! Claude Code の導入に失敗した可能性があります。上のログを確認してください。" -ForegroundColor Red
}

Write-Host ""
Write-Host "==> 3/4 GitHub にログインします。ブラウザが開いたら、許可された GitHub アカウントでログインしてください" -ForegroundColor Cyan
# 未ログインだと gh auth status は stderr に出力し終了コード非0（EAP=Continue なので止まらない）
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) { gh auth login --hostname github.com --git-protocol https --web }
gh auth setup-git
# ログインできていないと private リポジトリの取り込みに失敗するので、ここで確認する
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "  ! GitHub にログインできていません。もう一度この1行を実行してログインしてください。" -ForegroundColor Red
  return
}

Write-Host ""
Write-Host "==> 4/5 道具箱（daimaru-skills）を取り込んでいます" -ForegroundColor Cyan
Set-Location $HOME
if (-not (Test-Path "$HOME\daimaru-skills")) {
  git clone --recurse-submodules https://github.com/daimaru-d/daimaru-skills.git
} else {
  Write-Host "    既に取り込み済みです。最新へ更新します" -ForegroundColor DarkGray
  Set-Location "$HOME\daimaru-skills"
  git pull --recurse-submodules
}
# 取り込めたか確認（権限が無い等で失敗した場合のフォロー）
if (-not (Test-Path "$HOME\daimaru-skills\.git")) {
  Write-Host "  ! 道具箱を取り込めませんでした。多くは『閲覧権限が無い』ことが原因です。" -ForegroundColor Red
  Write-Host "    管理者に daimaru-d への read 権限付与を依頼してください。" -ForegroundColor Red
  return
}
Set-Location "$HOME\daimaru-skills"

Write-Host ""
Write-Host "==> 5/5 BIダッシュボード用の道具とログイン" -ForegroundColor Cyan
# gcloud / clasp / cloud-sql-proxy
if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
  winget install --id Google.CloudSDK -e --accept-package-agreements --accept-source-agreements
  Refresh-Path
}
Invoke-Cli npm @("install","-g","@google/clasp")
if (Get-Command gcloud -ErrorAction SilentlyContinue) {
  gcloud components install cloud-sql-proxy --quiet 2>$null   # 手動DL不要・自動でPATH
}
# DB接続ライブラリ(pg)
if (Test-Path "$HOME\daimaru-skills\repos\eigyo-talk-analyzer") {
  Push-Location "$HOME\daimaru-skills\repos\eigyo-talk-analyzer"
  Invoke-Cli npm @("ci")
  Pop-Location
}
# ログイン（ブラウザが開きます）
if (Get-Command gcloud -ErrorAction SilentlyContinue) {
  gcloud auth login 2>$null
  gcloud auth application-default login 2>$null   # ★ADC（proxyが使う。無いと401）
}
if (Get-Command clasp -ErrorAction SilentlyContinue) {
  if (-not (Test-Path "$HOME\.clasprc.json")) { clasp login 2>$null }
}
Write-Host "  ! 新規GAS作成には各自Googleで Apps Script API 有効化が必要: https://script.google.com/home/usersettings" -ForegroundColor Yellow

Write-Host ""
Write-Host "==> 準備ができました。Claude Code を起動します（安全バイパス：プロンプト最小・破壊操作はブロック）" -ForegroundColor Green
Write-Host "    起動後の流れ: bash .claude/skills/bi-dashboard/harness/bi-doctor.sh （自己診断）→ /bi-coach" -ForegroundColor Green
if (-not $script:PolicyOk) {
  Write-Host ""
  Write-Host "  【次回以降の起動について】この PC は組織ポリシーでスクリプト実行が制限されています。" -ForegroundColor Yellow
  Write-Host "  次回からは、フォルダ $HOME\daimaru-skills で  claude.cmd  と打って起動してください" -ForegroundColor Yellow
  Write-Host "  （ふつうの『claude』が使えない場合の回避策です）" -ForegroundColor Yellow
}
Write-Host ""
# claude.ps1 を避けて claude.cmd / claude.exe を起動（安全バイパス＝acceptEdits）
Invoke-Cli claude @("--permission-mode","acceptEdits")
