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
a="$(node -e 'let s=require(process.argv[1]);process.stdout.write(JSON.stringify(s.steps))' "$HOME/.daimaru-setup/state.json")"
check 'state 2回目も段は同じ' bash -c '. "$1/lib/common.sh"; K_ROLE=base; state_set x ok' _ "$ROOT"
b="$(node -e 'let s=require(process.argv[1]);process.stdout.write(JSON.stringify(s.steps))' "$HOME/.daimaru-setup/state.json")"
check 'state 冪等' test "$a" = "$b"
export OP_STUB_LOG="$T/op.log" OP_STUB_READ_VALUE='{"installed":{"client_id":"FAKE_ID","client_secret":"FAKE_SECRET_MUST_NOT_PRINT"}}'
: > "$OP_STUB_LOG"
out="$(PATH="$ROOT/tests/stubs:$PATH" bash -c '. "$1/lib/common.sh"; install_gws_secret && check_gws_secret' _ "$ROOT" 2>&1)"; rc=$?
secret_path="$HOME/.config/gws/client_secret.json"
if [ "$rc" = 0 ] && [ -f "$secret_path" ] && node -e 'process.exit((require("fs").statSync(process.argv[1]).mode&0o777)===0o600?0:1)' "$secret_path" && [[ "$out$(cat "$OP_STUB_LOG")" != *FAKE_SECRET_MUST_NOT_PRINT* ]]; then pass 'op read で秘密を直接 600 のファイルへ保存'; else fail 'op read で秘密を直接 600 のファイルへ保存'; fi
check 'op read の参照だけを引数にする' grep -qF 'ARGS=read op://Claude-Automation/gws-oauth-client/client_secret.json' "$OP_STUB_LOG"
mkdir -p "$HOME/.config/daimaru-op"
printf 'OP_VAULT=Shared-Vault\n' > "$HOME/.config/daimaru-op/config"
check '既存 OP_VAULT に合わせる' bash -c '. "$1/lib/common.sh"; [ "$(k_op_ref)" = "op://Shared-Vault/gws-oauth-client/client_secret.json" ]' _ "$ROOT"
mkdir -p "$T/hub/.claude/skills/alpha" "$T/hub/.claude/skills/beta" "$T/hub/profiles"
printf 'a' > "$T/hub/.claude/skills/alpha/SKILL.md"
printf 'b' > "$T/hub/.claude/skills/beta/SKILL.md"
printf '{"skills":["alpha"]}\n' > "$T/hub/profiles/base.json"
check 'profile 指定スキルだけコピー' bash -c '. "$1/lib/common.sh"; copy_skills "$2" base && [ -f "$HOME/.claude/skills/alpha/SKILL.md" ] && [ ! -e "$HOME/.claude/skills/beta" ]' _ "$ROOT" "$T/hub"
check 'profile json が無ければ従来どおり' bash -c '. "$1/lib/common.sh"; copy_skills "$2" sekkei' _ "$ROOT" "$T/hub"
printf '{"skills":["../beta"]}\n' > "$T/hub/profiles/base.json"
check '不正スキル名を拒否' bash -c '. "$1/lib/common.sh"; ! copy_skills "$2" base && [ ! -e "$HOME/.claude/skills/beta" ]' _ "$ROOT" "$T/hub"
mkdir -p "$HOME/Downloads"
printf 'FAKE_SECRET_MUST_NOT_PRINT' > "$HOME/Downloads/client_secret-test.json"
out="$(DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/doctor/doctor.sh" 2>&1)"; rc=$?
last="$(printf '%s\n' "$out" | tail -1)"
if [[ "$last" =~ ^DAIMARU_DOCTOR:\ (PASS|FAIL\ missing=[a-z0-9,-]+)$ ]] && { [ "$rc" = 0 ] || [ "$rc" = 2 ]; }; then pass 'doctor 最終行と終了コード'; else fail 'doctor 最終行と終了コード'; fi
if [[ "$out" != *FAKE_SECRET_MUST_NOT_PRINT* ]]; then pass 'doctor は秘密の中身を出さない'; else fail 'doctor は秘密の中身を出さない'; fi
for file in "$ROOT/setup.sh" "$ROOT/lib/common.sh" "$ROOT/doctor/doctor.sh" "$ROOT/tests/kitting.test.sh"; do check "bash -n ${file#"$ROOT"/}" bash -n "$file"; done
if [ -x /bin/bash ] && /bin/bash --version | head -1 | grep -q 'version 3'; then
  for file in "$ROOT/setup.sh" "$ROOT/lib/common.sh" "$ROOT/doctor/doctor.sh"; do check "bash 3.2 -n ${file#"$ROOT"/}" /bin/bash -n "$file"; done
fi
if command -v shellcheck >/dev/null 2>&1; then
  for file in "$ROOT/setup.sh" "$ROOT/lib/common.sh" "$ROOT/doctor/doctor.sh" "$ROOT/tests/kitting.test.sh"; do check "shellcheck ${file#"$ROOT"/}" shellcheck -S warning "$file"; done
fi
if command -v pwsh >/dev/null 2>&1; then
  for file in "$ROOT/setup.ps1" "$ROOT/lib/common.ps1" "$ROOT/doctor/doctor.ps1"; do
    check "PowerShell parse ${file#"$ROOT"/}" pwsh -NoProfile -Command '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile($args[0],[ref]$null,[ref]$e) | Out-Null; if ($e.Count) { $e | Out-String | Write-Host; exit 1 }' "$file"
  done
fi
for file in "$ROOT/setup.ps1" "$ROOT/lib/common.ps1" "$ROOT/doctor/doctor.ps1"; do
  check "CRLF・BOMなし ${file#"$ROOT"/}" node -e 'const b=require("fs").readFileSync(process.argv[1]);process.exit(b.subarray(0,3).equals(Buffer.from([239,187,191]))||!b.includes(Buffer.from("\r\n"))||b.toString().replace(/\r\n/g,"").includes("\n")?1:0)' "$file"
done
printf 'kitting: %s pass / %s fail\n' "$pass_n" "$fail_n"
[ "$fail_n" = 0 ]
