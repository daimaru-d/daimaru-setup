#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/kitting-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" USERPROFILE="$T/home"
mkdir -p "$HOME" "$T/bin"
export PATH="$T/bin:$PATH"
pass_n=0; fail_n=0
pass(){ pass_n=$((pass_n+1)); printf 'ok   %s\n' "$1"; }
fail(){ fail_n=$((fail_n+1)); printf 'FAIL %s\n' "$1"; }
check(){ local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
for role in base sekkei togo yochi somu-keiri; do
  check "profile $role" bash -c '. "$1/lib/common.sh"; profile_load "$1/profiles/$2.env" && [ -n "$ROLE_LABEL" ] && [ -n "$TOOLS" ]' _ "$ROOT" "$role"
done
check '非対話の既定役割 base' bash -c '. "$1/lib/common.sh"; unset DAIMARU_ROLE; role_select && [ "$K_ROLE" = base ]' _ "$ROOT" </dev/null
check '不正な役割を拒否' bash -c '. "$1/lib/common.sh"; DAIMARU_ROLE=../x; ! role_select' _ "$ROOT" </dev/null
printf 'ROLE_LABEL=$(touch %s/pwned)\nTOOLS=git\n' "$T" > "$T/safe.env"
check 'profile はコード実行しない' bash -c '. "$1/lib/common.sh"; profile_load "$2" && [ "$ROLE_LABEL" != "" ] && [ ! -e "$3/pwned" ]' _ "$ROOT" "$T/safe.env" "$T"
for role in base sekkei togo yochi somu-keiri; do
  out="$(DAIMARU_ROLE="$role" DAIMARU_DRY_RUN=1 bash "$ROOT/setup.sh" </dev/null 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && [[ "$out" == *"予定:"* ]] && [ ! -e "$HOME/.daimaru-setup" ] && [ ! -e "$HOME/daimaru-skills" ]; then pass "DRY_RUN $role は変更なし"; else fail "DRY_RUN $role は変更なし"; fi
done
check 'DRY_RUN 不正役割を拒否' bash -c 'DAIMARU_DRY_RUN=1 DAIMARU_ROLE=../bad bash "$1/setup.sh" >/dev/null 2>&1; [ $? = 2 ]' _ "$ROOT"
printf '#!/bin/sh\nexit 77\n' > "$T/bin/curl"
chmod +x "$T/bin/curl"
out="$(cd "$T" && DAIMARU_DRY_RUN=1 DAIMARU_ROLE=togo bash < "$ROOT/setup.sh" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [[ "$out" == *clasp* ]] && [ ! -e "$HOME/.daimaru-setup" ]; then pass 'pipe 実行の DRY_RUN は通信しない'; else fail 'pipe 実行の DRY_RUN は通信しない'; fi
check 'state の役割・段を記録' bash -c '. "$1/lib/common.sh"; K_ROLE=base; state_set x ok && [ "$(state_get x)" = ok ]' _ "$ROOT"
a="$(node -e 'let s=require(process.argv[1]);process.stdout.write(JSON.stringify(s.steps))' "$HOME/.config/daimaru-setup/state.json")"
check 'state 2回目も段は同じ' bash -c '. "$1/lib/common.sh"; K_ROLE=base; state_set x ok' _ "$ROOT"
b="$(node -e 'let s=require(process.argv[1]);process.stdout.write(JSON.stringify(s.steps))' "$HOME/.config/daimaru-setup/state.json")"
check 'state 冪等' test "$a" = "$b"
check 'state は clone 先を占有しない' test ! -e "$HOME/.daimaru-setup"
rm -f "$HOME/.config/daimaru-setup/state.json"
mkdir -p "$HOME/.daimaru-setup"
printf '{"role":"base","steps":{"legacy":"ok"}}\n' > "$HOME/.daimaru-setup/state.json"
check '旧 state を新しい場所へ移動' bash -c '. "$1/lib/common.sh"; K_ROLE=base; [ "$(state_get legacy)" = ok ] && [ ! -e "$HOME/.daimaru-setup/state.json" ]' _ "$ROOT"
export OP_STUB_LOG="$T/op.log" OP_STUB_READ_VALUE='{"installed":{"client_id":"FAKE_ID","client_secret":"FAKE_SECRET_MUST_NOT_PRINT"}}'
: > "$OP_STUB_LOG"
out="$(PATH="$ROOT/tests/stubs:$PATH" bash -c '. "$1/lib/common.sh"; install_gws_secret && check_gws_secret' _ "$ROOT" 2>&1)"; rc=$?
secret_path="$HOME/.config/gws/client_secret.json"
if [ "$rc" = 0 ] && [ -f "$secret_path" ] && node -e 'process.exit((require("fs").statSync(process.argv[1]).mode&0o777)===0o600?0:1)' "$secret_path" && [[ "$out$(cat "$OP_STUB_LOG")" != *FAKE_SECRET_MUST_NOT_PRINT* ]]; then pass 'op read で秘密を直接 600 のファイルへ保存'; else fail 'op read で秘密を直接 600 のファイルへ保存'; fi
chmod 644 "$secret_path"
check '既存 OAuth 設定の権限を再び 600 にする' bash -c '. "$1/lib/common.sh"; check_gws_secret && node -e '\''process.exit((require("fs").statSync(process.argv[1]).mode&0o777)===0o600?0:1)'\'' "$2"' _ "$ROOT" "$secret_path"
check 'op read の参照だけを引数にする' grep -qF 'ARGS=read op://Claude-Automation/gws-oauth-client/client_secret.json' "$OP_STUB_LOG"
mkdir -p "$HOME/.config/daimaru-op"
printf 'OP_VAULT=Shared-Vault\n' > "$HOME/.config/daimaru-op/config"
check '既存 OP_VAULT に合わせる' bash -c '. "$1/lib/common.sh"; [ "$(k_op_ref)" = "op://Shared-Vault/gws-oauth-client/client_secret.json" ]' _ "$ROOT"
mkdir -p "$T/hub/.claude/skills/alpha" "$T/hub/.claude/skills/beta" "$T/hub/profiles"
printf 'a' > "$T/hub/.claude/skills/alpha/SKILL.md"
printf 'b' > "$T/hub/.claude/skills/beta/SKILL.md"
printf '{"skills":["alpha"]}\n' > "$T/hub/profiles/base.json"
check 'profile 指定スキルだけコピー' bash -c '. "$1/lib/common.sh"; copy_skills "$2" base && [ -f "$HOME/.claude/skills/alpha/SKILL.md" ] && [ ! -e "$HOME/.claude/skills/beta" ]' _ "$ROOT" "$T/hub"
mkdir -p "$HOME/.claude/skills/alpha/stale"
printf 'old' > "$HOME/.claude/skills/alpha/stale/obsolete"
check 'スキル更新で二重ネストと古いファイルを残さない' bash -c '. "$1/lib/common.sh"; copy_skills "$2" base && [ -f "$HOME/.claude/skills/alpha/SKILL.md" ] && [ ! -e "$HOME/.claude/skills/alpha/alpha" ] && [ ! -e "$HOME/.claude/skills/alpha/stale" ]' _ "$ROOT" "$T/hub"
check 'profile json が無ければ従来どおり' bash -c '. "$1/lib/common.sh"; copy_skills "$2" sekkei' _ "$ROOT" "$T/hub"
printf '{"skills":["../beta"]}\n' > "$T/hub/profiles/base.json"
check '不正スキル名を拒否' bash -c '. "$1/lib/common.sh"; ! copy_skills "$2" base && [ ! -e "$HOME/.claude/skills/beta" ]' _ "$ROOT" "$T/hub"
mkdir -p "$HOME/Downloads"
printf 'FAKE_SECRET_MUST_NOT_PRINT' > "$HOME/Downloads/client_secret-test.json"
out="$(DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/doctor/doctor.sh" 2>&1)"; rc=$?
last="$(printf '%s\n' "$out" | tail -1)"
if [[ "$last" =~ ^DAIMARU_DOCTOR:\ (PASS|FAIL\ missing=[a-z0-9,-]+)$ ]] && { [ "$rc" = 0 ] || [ "$rc" = 2 ]; }; then pass 'doctor 最終行と終了コード'; else fail 'doctor 最終行と終了コード'; fi
if [[ "$out" != *FAKE_SECRET_MUST_NOT_PRINT* ]]; then pass 'doctor は秘密の中身を出さない'; else fail 'doctor は秘密の中身を出さない'; fi
out="$(DAIMARU_ROLE=togo DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/doctor/doctor.sh" 2>&1)"
check 'togo は clasp ログインと proxy の不足を列挙' bash -c '[[ "$1" == *"missing="* ]] && [[ "$1" == *"clasp-login"* ]] && [[ "$1" == *"cloud-sql-proxy"* ]]' _ "$out"
check '不正な配布 URL を拒否' bash -c 'DAIMARU_SETUP_BASE=http://example.invalid DAIMARU_DRY_RUN=1 bash "$1/setup.sh" >/dev/null 2>&1; [ $? = 2 ]' _ "$ROOT"
check 'file URL はテスト指定時だけ許可' bash -c 'DAIMARU_SETUP_BASE=file:///tmp DAIMARU_DRY_RUN=1 bash "$1/setup.sh" >/dev/null 2>&1; [ $? = 2 ] && DAIMARU_SETUP_ALLOW_FILE=1 DAIMARU_SETUP_BASE=file:///tmp DAIMARU_DRY_RUN=1 bash "$1/setup.sh" >/dev/null 2>&1' _ "$ROOT"
out="$(cd "$T" && PATH="${PATH#"$T/bin:"}" DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 DAIMARU_SETUP_ALLOW_FILE=1 DAIMARU_SETUP_BASE="file://$ROOT" bash < "$ROOT/doctor/doctor.sh" 2>&1)"; rc=$?
if { [ "$rc" = 0 ] || [ "$rc" = 2 ]; } && [[ "$out" == *'daimaru-setup 診断'* ]] && [[ "$out" == *'DAIMARU_DOCTOR:'* ]]; then pass 'doctor は pipe 単独実行で共通部品を取得'; else fail 'doctor は pipe 単独実行で共通部品を取得'; fi
for file in "$ROOT/setup.sh" "$ROOT/lib/common.sh" "$ROOT/doctor/doctor.sh" "$ROOT/tests/kitting.test.sh"; do check "bash -n ${file#"$ROOT"/}" bash -n "$file"; done
if [ -x /bin/bash ] && /bin/bash --version | head -1 | grep -q 'version 3'; then
  for file in "$ROOT/setup.sh" "$ROOT/lib/common.sh" "$ROOT/doctor/doctor.sh"; do check "bash 3.2 -n ${file#"$ROOT"/}" /bin/bash -n "$file"; done
fi
if command -v shellcheck >/dev/null 2>&1; then
  for file in "$ROOT/setup.sh" "$ROOT/lib/common.sh" "$ROOT/doctor/doctor.sh" "$ROOT/tests/kitting.test.sh"; do check "shellcheck ${file#"$ROOT"/}" shellcheck -S warning "$file"; done
fi
if command -v pwsh >/dev/null 2>&1; then
  printf '{"skills":["alpha"]}\n' > "$T/hub/profiles/base.json"
  for role in base sekkei togo yochi somu-keiri; do
    out="$(APPDATA="$T/appdata" DAIMARU_ROLE="$role" DAIMARU_DRY_RUN=1 pwsh -NoProfile -File "$ROOT/setup.ps1" 2>&1)"; rc=$?
    if [ "$rc" = 0 ] && [[ "$out" == *'予定の表示を完了しました'* ]]; then pass "PowerShell DRY_RUN $role"; else fail "PowerShell DRY_RUN $role"; fi
  done
  while IFS= read -r file; do
    check "PowerShell parse ${file#"$ROOT"/}" env K_PARSE_FILE="$file" pwsh -NoProfile -Command '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile($env:K_PARSE_FILE,[ref]$null,[ref]$e) | Out-Null; if ($e.Count) { $e | Out-String | Write-Host; exit 1 }'
  done < <(find "$ROOT" -name '*.ps1' -type f -print)
  check 'PowerShell スキル更新は二重ネストしない' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_TEST_HUB="$T/hub" pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; . $env:K_COMMON_FILE; if (-not (Copy-RoleSkills $env:K_TEST_HUB base)) { exit 1 }; if (Test-Path (Join-Path $HOME ".claude/skills/alpha/alpha")) { exit 1 }'
  check 'PowerShell 5.1 用 gws JSON エスケープ' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_EXPECTED_GWS='{\"pageSize\":1,\"fields\":\"files(id)\"}' pwsh -NoProfile -Command '. $env:K_COMMON_FILE; $PSVersionTable.PSVersion=[version]"5.1"; function Invoke-Cli([string]$Name,[string[]]$CliArgs) { $CliArgs[-1] }; if ((Invoke-Gws @("drive","files","list")) -cne $env:K_EXPECTED_GWS) { exit 1 }'
  printf '\357\273\277Write-Output "UTF8"\n' > "$T/remote.ps1"
  check 'PowerShell の再取得コードは先頭 BOM を除く' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_REMOTE_FILE="file://$T/remote.ps1" pwsh -NoProfile -Command '. $env:K_COMMON_FILE; $code=Get-RemoteScript $env:K_REMOTE_FILE; if ($code[0] -eq [char]0xFEFF -or (Invoke-Expression $code) -ne "UTF8") { exit 1 }'
  out="$(APPDATA="$T/appdata" DAIMARU_SETUP_ROOT='' DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 K_SOURCE_ROOT="$ROOT" K_DOCTOR_FILE="$ROOT/doctor/doctor.ps1" pwsh -NoProfile -Command 'function Invoke-WebRequest { param([string]$Uri,[string]$OutFile,[switch]$UseBasicParsing) $rel=if ($Uri -match "/lib/common.ps1$") { "lib/common.ps1" } elseif ($Uri -match "/profiles/base.env$") { "profiles/base.env" } else { throw "unexpected URL" }; Copy-Item (Join-Path $env:K_SOURCE_ROOT $rel) $OutFile }; Invoke-Expression ([IO.File]::ReadAllText($env:K_DOCTOR_FILE,[Text.Encoding]::UTF8))' 2>&1)"; rc=$?
  if { [ "$rc" = 0 ] || [ "$rc" = 2 ]; } && [[ "$out" == *'daimaru-setup 診断'* ]] && [[ "$out" == *'DAIMARU_DOCTOR:'* ]]; then pass 'PowerShell doctor は iex 単独実行で共通部品を取得'; else fail 'PowerShell doctor は iex 単独実行で共通部品を取得'; fi
fi
for file in "$ROOT/setup.ps1" "$ROOT/lib/common.ps1" "$ROOT/doctor/doctor.ps1"; do
  check "CRLF・BOMあり ${file#"$ROOT"/}" node -e 'const b=require("fs").readFileSync(process.argv[1]);process.exit(!b.subarray(0,3).equals(Buffer.from([239,187,191]))||!b.includes(Buffer.from("\r\n"))||b.toString().replace(/\r\n/g,"").includes("\n")?1:0)' "$file"
done
printf 'kitting: %s pass / %s fail\n' "$pass_n" "$fail_n"
[ "$fail_n" = 0 ]
