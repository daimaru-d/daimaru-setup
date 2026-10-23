# ============================================================
# パスワード金庫（1Password）を Claude Code で使えるようにする - Windows用
# 使い方: PowerShell に次の1行を貼って Enter
#   irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/setup.ps1 | iex
# やること: 1Password CLI の導入 → daimaru-setup の取り込み → Git Bash で op-secrets を Claude Code に入れる
# パスワードやトークンは一切扱いません。
# ============================================================
# irm | iex で配るため BOM なし UTF-8・param なし（scripts/keiri/onboard.ps1 と同じ理由）。
# irm | iex は貼り付けた PowerShell のスコープで動くので、変数を散らかさないよう全体を関数の中に置き、
# 窓を閉じないよう exit ではなく return で終える。
function Install-DaimaruOpSecrets {
  $ErrorActionPreference = "Continue"
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

  # winget でソフトを入れた直後は PATH が未反映になるため、都度読み直す（setup.ps1 と同じ）
  function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path","User")
  }

  $opRepo = if ($env:DAIMARU_SETUP_REPO) { $env:DAIMARU_SETUP_REPO } else { "https://github.com/daimaru-d/daimaru-setup" }
  $opDir  = if ($env:DAIMARU_SETUP_DIR) { $env:DAIMARU_SETUP_DIR } else { Join-Path $HOME ".daimaru-setup" }

  Write-Host ""
  Write-Host "==> 1Password CLI（op）を入れています" -ForegroundColor Cyan
  if (Get-Command op.exe -ErrorAction SilentlyContinue) {
    Write-Host "  ✓ 1Password CLI は入っています" -ForegroundColor Green
  } else {
    winget install --id AgileBits.1Password.CLI -e --accept-package-agreements --accept-source-agreements
    Refresh-Path
    if (-not (Get-Command op.exe -ErrorAction SilentlyContinue)) {
      Write-Host "  ! 1Password CLI がまだ見つかりません。PowerShell を開き直してから、もう一度この1行を実行してください" -ForegroundColor Yellow
    }
  }
  # アプリ本体は会社の配布方針があり得るので自動では入れない（案内だけ）
  $opApp = @(
    (Join-Path $env:LOCALAPPDATA "1Password\app\8\1Password.exe"),
    (Join-Path $env:ProgramFiles "1Password\app\8\1Password.exe")
  ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if (-not $opApp) {
    Write-Host "  ! 1Password アプリが見つかりません。会社の手順に従って入れてください（例: winget install --id AgileBits.1Password -e）" -ForegroundColor Yellow
  }

  Write-Host ""
  Write-Host "==> Git Bash を探しています" -ForegroundColor Cyan
  $bash = $null
  $git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($git) {
    $cand = Join-Path (Split-Path (Split-Path $git.Source -Parent) -Parent) "bin\bash.exe"
    if (Test-Path $cand) { $bash = $cand }
  }
  if (-not $bash -and (Test-Path "C:\Program Files\Git\bin\bash.exe")) { $bash = "C:\Program Files\Git\bin\bash.exe" }
  if (-not $bash) {
    Write-Host "  ! Git Bash が見つかりません。先に daimaru-setup の本体の1行（setup.ps1）を実行してください" -ForegroundColor Red
    return
  }
  Write-Host "  ✓ $bash" -ForegroundColor Green

  Write-Host ""
  Write-Host "==> 道具（daimaru-setup）を取り込んでいます" -ForegroundColor Cyan
  if (Test-Path (Join-Path $opDir ".git")) {
    git -C $opDir pull --ff-only 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "  ! 更新に失敗しました（古いまま続けます）" -ForegroundColor Yellow }
  } else {
    git clone --depth 1 $opRepo $opDir 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  ! 取り込みに失敗しました。ネットワークを確認して、もう一度この1行を実行してください" -ForegroundColor Red
      return
    }
  }

  Write-Host ""
  Write-Host "==> op-secrets を Claude Code に入れています" -ForegroundColor Cyan
  $installSh = (Join-Path $opDir "skills\op-secrets\scripts\install.sh") -replace '\\','/'
  & $bash $installSh
  if ($LASTEXITCODE -ne 0) { Write-Host "  ! op-secrets の導入で問題がありました（上の表示を確認してください）" -ForegroundColor Yellow }

  Write-Host ""
  Write-Host "==> 1Password アプリ側でやること（最初の1回だけ）" -ForegroundColor Cyan
  Write-Host "  1. 1Password アプリで daimaruenterprise.1password.com にサインイン"
  Write-Host "  2. アプリの 設定 → 開発者 → 「1Password CLI と連携」を ON"
  Write-Host "  3. 確認（Git Bash で）: bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh"
}

Install-DaimaruOpSecrets
