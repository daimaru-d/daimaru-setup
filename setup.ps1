# ============================================================
# 大丸 業務ハブ（daimaru-skills）初期セットアップ - Windows用
# 使い方: PowerShell に次の1行を貼って Enter するだけ
#   irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.ps1 | iex
# ============================================================
$ErrorActionPreference = "Stop"

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

Write-Host ""
Write-Host "==> 3/4 GitHub にログインします。ブラウザが開いたら、許可された GitHub アカウントでログインしてください" -ForegroundColor Cyan
gh auth status 2>$null
if ($LASTEXITCODE -ne 0) { gh auth login --hostname github.com --git-protocol https --web }
gh auth setup-git

Write-Host ""
Write-Host "==> 4/4 道具箱（daimaru-skills）を取り込んでいます" -ForegroundColor Cyan
Set-Location $HOME
if (-not (Test-Path "$HOME\daimaru-skills")) {
  git clone --recurse-submodules https://github.com/daimaru-d/daimaru-skills.git
} else {
  Write-Host "    既に取り込み済みです。最新へ更新します" -ForegroundColor DarkGray
  Set-Location "$HOME\daimaru-skills"
  git pull --recurse-submodules
}
Set-Location "$HOME\daimaru-skills"

Write-Host ""
Write-Host "==> 準備ができました。Claude Code を起動します" -ForegroundColor Green
Write-Host "    起動後、最初に /setup と打つと全業務の中身がそろいます" -ForegroundColor Green
if (-not $script:PolicyOk) {
  Write-Host ""
  Write-Host "  【次回以降の起動について】この PC は組織ポリシーでスクリプト実行が制限されています。" -ForegroundColor Yellow
  Write-Host "  次回からは、フォルダ $HOME\daimaru-skills で  claude.cmd  と打って起動してください" -ForegroundColor Yellow
  Write-Host "  （ふつうの『claude』が使えない場合の回避策です）" -ForegroundColor Yellow
}
Write-Host ""
# claude.ps1 を避けて claude.cmd / claude.exe を起動
Invoke-Cli claude @()
