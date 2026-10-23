#!/usr/bin/env bash
# =============================================================================
# op-sa-token.sh — サービスアカウントのトークンを OS の金庫に保管する（無人実行用）
#   使い方: op-sa-token.sh set     … トークンを非表示で入力して保管
#           op-sa-token.sh status  … 保管されているか（あり/なし）だけ表示
#           op-sa-token.sh clear   … 削除
#   （内部）source して ops_sa_load を呼ぶと OP_SERVICE_ACCOUNT_TOKEN を export する（表示しない）
# 保管先: Mac=キーチェーン / Windows=DPAPI で暗号化したファイル（そのユーザーしか復号できない）
#         Linux=secret-tool（無ければ ~/.config/daimaru-op/sa-token を 0600 で置き、警告）
# トークンは 1Password の管理者が発行する。値は画面・ログ・ファイル名・引数に出さない
#   ※ Mac の security コマンドだけは -w の引数で渡す（標準入力で受ける方法が無いため）。
#     この引数が見えるのは security が動いている一瞬だけで、表示やログには残らない。
# =============================================================================
OPS_SA_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$OPS_SA_HERE/lib.sh"

OPS_SA_SERVICE="daimaru-op-sa"
OPS_SA_FILE="$OPS_CONFIG_DIR/sa-token"

ops_sa_user(){ printf '%s' "${USER:-${USERNAME:-$(id -un 2>/dev/null || echo user)}}"; }

# 保管先の種類。DAIMARU_OP_SA_BACKEND で固定できる（テスト用: file）
ops_sa_backend(){
  local b="${DAIMARU_OP_SA_BACKEND:-auto}"
  if [ "$b" = auto ]; then
    case "$OPS_OS" in
      mac) b=keychain;;
      win) b=dpapi;;
      *) if have secret-tool; then b="secret-tool"; else b="file"; fi;;
    esac
  fi
  printf '%s' "$b"
}

# PowerShell の中身（引数にはスクリプトだけを渡し、トークンは標準入出力でやり取りする）
OPS_SA_PS_STORE='$t = [Console]::In.ReadToEnd().Trim(); if (-not $t) { exit 1 }
$d = Join-Path $env:LOCALAPPDATA "daimaru-op"; New-Item -ItemType Directory -Force -Path $d | Out-Null
$t | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Set-Content -Path (Join-Path $d "sa-token.dpapi")
Remove-Variable t'
OPS_SA_PS_LOAD='$p = Join-Path $env:LOCALAPPDATA "daimaru-op\sa-token.dpapi"; if (-not (Test-Path $p)) { exit 1 }
$s = (Get-Content -Raw $p).Trim() | ConvertTo-SecureString
$b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
try { [Console]::Out.Write([Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }'
OPS_SA_PS_TEST='if (Test-Path (Join-Path $env:LOCALAPPDATA "daimaru-op\sa-token.dpapi")) { exit 0 } else { exit 1 }'
OPS_SA_PS_CLEAR='Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $env:LOCALAPPDATA "daimaru-op\sa-token.dpapi")'

# 保管（トークンは変数 OPS_SA_TOKEN_IN から受け取る）
ops_sa_store(){
  local b; b="$(ops_sa_backend)"
  case "$b" in
    keychain) security add-generic-password -U -s "$OPS_SA_SERVICE" -a "$(ops_sa_user)" -w "$OPS_SA_TOKEN_IN" >/dev/null 2>&1;;
    dpapi)    printf '%s' "$OPS_SA_TOKEN_IN" | powershell.exe -NoProfile -NonInteractive -Command "$OPS_SA_PS_STORE" >/dev/null;;
    secret-tool) printf '%s' "$OPS_SA_TOKEN_IN" | secret-tool store --label="$OPS_SA_SERVICE" service "$OPS_SA_SERVICE" account "$(ops_sa_user)";;
    file)
      mkdir -p "$OPS_CONFIG_DIR" && chmod 700 "$OPS_CONFIG_DIR" 2>/dev/null
      ( umask 077; printf '%s' "$OPS_SA_TOKEN_IN" > "$OPS_SA_FILE" ) && chmod 600 "$OPS_SA_FILE"
      [ "${DAIMARU_OP_SA_BACKEND:-auto}" = file ] || warn "OS の金庫（secret-tool）が無いため、${OPS_SA_FILE}（本人だけ読める設定）に置きました";;
    *) return 1;;
  esac
}

# 読み出し → OP_SERVICE_ACCOUNT_TOKEN を export（表示しない）
ops_sa_load(){
  local b t=""; b="$(ops_sa_backend)"
  case "$b" in
    keychain) t="$(security find-generic-password -s "$OPS_SA_SERVICE" -a "$(ops_sa_user)" -w 2>/dev/null)" || return 1;;
    dpapi)    t="$(powershell.exe -NoProfile -NonInteractive -Command "$OPS_SA_PS_LOAD" 2>/dev/null)" || return 1;;
    secret-tool) t="$(secret-tool lookup service "$OPS_SA_SERVICE" account "$(ops_sa_user)" 2>/dev/null)" || return 1;;
    file) [ -s "$OPS_SA_FILE" ] || return 1; t="$(< "$OPS_SA_FILE")";;
    *) return 1;;
  esac
  t="${t%$'\r'}"; t="${t%$'\n'}"
  [ -n "$t" ] || return 1
  OP_SERVICE_ACCOUNT_TOKEN="$t"
  t=""
  export OP_SERVICE_ACCOUNT_TOKEN
}

ops_sa_exists(){
  local b; b="$(ops_sa_backend)"
  case "$b" in
    keychain) security find-generic-password -s "$OPS_SA_SERVICE" -a "$(ops_sa_user)" >/dev/null 2>&1;;
    dpapi)    powershell.exe -NoProfile -NonInteractive -Command "$OPS_SA_PS_TEST" >/dev/null 2>&1;;
    secret-tool) secret-tool lookup service "$OPS_SA_SERVICE" account "$(ops_sa_user)" >/dev/null 2>&1;;
    file) [ -s "$OPS_SA_FILE" ];;
    *) return 1;;
  esac
}

ops_sa_clear(){
  local b; b="$(ops_sa_backend)"
  case "$b" in
    keychain) security delete-generic-password -s "$OPS_SA_SERVICE" -a "$(ops_sa_user)" >/dev/null 2>&1 || true;;
    dpapi)    powershell.exe -NoProfile -NonInteractive -Command "$OPS_SA_PS_CLEAR" >/dev/null 2>&1 || true;;
    secret-tool) secret-tool clear service "$OPS_SA_SERVICE" account "$(ops_sa_user)" >/dev/null 2>&1 || true;;
    file) if [ -f "$OPS_SA_FILE" ]; then : > "$OPS_SA_FILE"; rm -f "$OPS_SA_FILE"; fi;;
  esac
}

ops_sa_main(){
  set -uo pipefail
  case "${1:-}" in
    set)
      OPS_SA_TOKEN_IN=""
      IFS= read -r -s -p "サービスアカウントのトークン（表示されません）: " OPS_SA_TOKEN_IN || true
      printf '\n' >&2
      OPS_SA_TOKEN_IN="${OPS_SA_TOKEN_IN%$'\r'}"
      if [ -z "$OPS_SA_TOKEN_IN" ]; then err "空のため保管しませんでした"; return 2; fi
      if ops_sa_store; then ok "保管しました（保管先: $(ops_sa_backend)）。無人実行は OP_SA_MODE=1 で使います"; OPS_SA_TOKEN_IN=""
      else OPS_SA_TOKEN_IN=""; err "保管に失敗しました（保管先: $(ops_sa_backend)）"; return 2; fi;;
    status)
      if ops_sa_exists; then echo "サービスアカウントのトークン: あり（保管先: $(ops_sa_backend)）"
      else echo "サービスアカウントのトークン: なし（保管先: $(ops_sa_backend)）"; return 2; fi;;
    clear)
      ops_sa_clear; ok "削除しました（保管先: $(ops_sa_backend)）";;
    load)
      err "load は内部用です（値を表示しないため、source して ops_sa_load を呼びます）"; return 2;;
    *)
      echo "使い方: op-sa-token.sh set | status | clear" >&2; return 2;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  ops_sa_main "$@"
  exit $?
fi
