# ============================================================
# 大丸 業務ハブ（daimaru-skills）初期セットアップ - Windows用
# 使い方: PowerShell に次の1行を貼って Enter するだけ
#   irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.ps1 | iex
# ============================================================
$ErrorActionPreference = "Stop"

# winget でソフトを入れた直後は PATH が未反映になるため、都度読み直す
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
              [Environment]::GetEnvironmentVariable("Path","User")
}

Write-Host ""
Write-Host "==> 1/4 必要なソフトを入れています (Git / Node.js / GitHub CLI)" -ForegroundColor Cyan
winget install --id Git.Git           -e --accept-package-agreements --accept-source-agreements
winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
winget install --id GitHub.cli        -e --accept-package-agreements --accept-source-agreements
Refresh-Path

Write-Host ""
Write-Host "==> 2/4 Claude Code を入れています" -ForegroundColor Cyan
npm install -g @anthropic-ai/claude-code
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
Write-Host ""
claude
