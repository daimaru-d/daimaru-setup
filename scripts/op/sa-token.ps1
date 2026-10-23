# ============================================================
# 無人実行用のトークン（1Password のサービスアカウント）をこの PC に入れる - Windows用
# 使い方: 管理者が対象の PC の PowerShell に次の1行を貼って Enter
#   irm https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/sa-token.ps1 | iex
# トークンは表示されない入力欄で受け、DPAPI で暗号化して保存する（このユーザーしか復号できない）。
# 保存先と形式は skills/op-secrets/scripts/op-sa-token.sh（Windows）と同じ:
#   %LOCALAPPDATA%\daimaru-op\sa-token.dpapi
# ============================================================
# irm | iex で配るため BOM なし UTF-8・param なし。変数を散らかさないよう関数の中に置き、return で終える。
function Set-DaimaruOpSaToken {
  $ErrorActionPreference = "Continue"
  Write-Host ""
  Write-Host "==> 無人実行用のトークン（1Password のサービスアカウント）を保存します" -ForegroundColor Cyan
  $sec = Read-Host -AsSecureString "トークンを貼り付けて Enter（表示されません）"
  if (-not $sec -or $sec.Length -eq 0) {
    Write-Host "  ! 空のため保存しませんでした" -ForegroundColor Yellow
    return
  }
  $dir = Join-Path $env:LOCALAPPDATA "daimaru-op"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $file = Join-Path $dir "sa-token.dpapi"
  try {
    $sec | ConvertFrom-SecureString | Set-Content -Path $file
  } catch {
    Write-Host "  ! 保存に失敗しました: $($_.Exception.Message)" -ForegroundColor Red
    return
  } finally {
    $sec.Dispose()
  }
  if (Test-Path $file) {
    Write-Host "サービスアカウントのトークン: あり（保管先: dpapi）" -ForegroundColor Green
    Write-Host "  無人実行に切り替えるには、~/.config/daimaru-op/config の OP_SA_MODE を 1 にします（Claude に「この PC を無人実行に切り替えて」と頼めます）"
  } else {
    Write-Host "サービスアカウントのトークン: なし（保管先: dpapi）" -ForegroundColor Red
  }
}

Set-DaimaruOpSaToken
