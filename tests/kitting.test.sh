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
contains(){ case "$1" in *"$2"*) return 0;; esac; return 1; }
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
check '保存済み役割を既定に使い明示指定を優先' bash -c '. "$1/lib/common.sh"; unset DAIMARU_ROLE; role_select && [ "$K_ROLE" = base ] && DAIMARU_ROLE=togo role_select && [ "$K_ROLE" = togo ]' _ "$ROOT" </dev/null
check '認可スコープは順序と追加を判定' bash -c '. "$1/lib/common.sh"; K_ROLE=yochi; state_set_scopes gmail,drive && scopes_cover "$(state_scopes)" drive,gmail && ! scopes_cover "$(state_scopes)" drive,gmail,calendar' _ "$ROOT"
printf '#!/bin/sh\n"$@"\n' > "$T/bin/sudo"
cat > "$T/bin/apt-get" <<'STUB'
#!/bin/sh
printf '%s|%s|%s|%s|%s\n' "$#" "$1" "$2" "$3" "$4" >> "$K_PKG_LOG"
STUB
cp "$T/bin/apt-get" "$T/bin/dnf"
chmod +x "$T/bin/sudo" "$T/bin/apt-get" "$T/bin/dnf"
export K_PKG_LOG="$T/packages.log"
: > "$K_PKG_LOG"
check 'Linux nodejs と npm を別引数で渡す' bash -c '. "$1/lib/common.sh"; K_PM=apt; install_pkg node "nodejs npm"; K_PM=dnf; install_pkg node "nodejs npm"; [ "$(grep -cFx "4|install|-y|nodejs|npm" "$K_PKG_LOG")" = 2 ]' _ "$ROOT"
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
check 'op read の参照だけを引数にする' grep -qF 'ARGS=--account daimaruenterprise.1password.com read op://Claude-Automation/gws-oauth-client/client_secret.json' "$OP_STUB_LOG"
check '共有 OAuth が壊れていても一時ファイルを残さず既存 secret を守る' bash -c 'OP_STUB_READ_VALUE=broken PATH="$1/tests/stubs:$PATH" bash -c '\'' . "$1/lib/common.sh"; ! install_gws_secret '\'' _ "$1" >/dev/null 2>&1; [ -f "$2" ] && ! ls "${2%/*}/.client_secret-"* >/dev/null 2>&1' _ "$ROOT" "$secret_path"
check 'サービスアカウントは account 指定を付けない' bash -c 'OP_SERVICE_ACCOUNT_TOKEN=test PATH="$1/tests/stubs:$PATH" bash -c '\'' . "$1/lib/common.sh"; install_gws_secret '\'' _ "$1" >/dev/null 2>&1; grep -qFx "SA=1 ARGS=read op://Claude-Automation/gws-oauth-client/client_secret.json" "$OP_STUB_LOG"' _ "$ROOT"
mkdir -p "$HOME/.config/daimaru-op"
printf 'OP_VAULT=Shared-Vault\nOP_ACCOUNT=team.1password.com\n' > "$HOME/.config/daimaru-op/config"
check '既存 OP_VAULT に合わせる' bash -c '. "$1/lib/common.sh"; [ "$(k_op_ref)" = "op://Shared-Vault/gws-oauth-client/client_secret.json" ]' _ "$ROOT"
check '設定された 1Password account を使用' bash -c 'PATH="$1/tests/stubs:$PATH" bash -c '\'' . "$1/lib/common.sh"; install_gws_secret '\'' _ "$1" >/dev/null 2>&1; grep -qF "ARGS=--account team.1password.com read op://Shared-Vault/" "$OP_STUB_LOG"' _ "$ROOT"
mkdir -p "$T/hub/.git/info" "$T/hub/repos/demo" "$T/hub/.claude/skills/alpha" "$T/hub/.claude/skills/beta" "$T/hub/profiles"
printf 'a' > "$T/hub/.claude/skills/alpha/SKILL.md"
printf 'b' > "$T/hub/.claude/skills/beta/SKILL.md"
printf '{"skills":["alpha"]}\n' > "$T/hub/profiles/base.json"
printf '{}' > "$T/hub/.claude/settings.json"
printf 'hub instructions\n' > "$T/hub/CLAUDE.md"
printf 'repo content\n' > "$T/hub/repos/demo/readme"
check '役割ワークスペースには指定スキルと設定だけ' bash -c '. "$1/lib/common.sh"; copy_skills "$2" base && [ -f "$2/.workspaces/base/.claude/skills/alpha/SKILL.md" ] && [ ! -e "$2/.workspaces/base/.claude/skills/beta" ] && [ -f "$2/.workspaces/base/.claude/settings.json" ] && [ "$(role_workspace "$2" base)" = "$2/.workspaces/base" ]' _ "$ROOT" "$T/hub"
check 'hub の文書と repos をワークスペースから参照' bash -c '. "$1/lib/common.sh"; [ -f "$2/.workspaces/base/CLAUDE.md" ] && [ -f "$2/.workspaces/base/repos/demo/readme" ] && [ ! -L "$2/.workspaces/base/.claude/skills/alpha" ] && grep -qxF .workspaces/ "$2/.git/info/exclude"' _ "$ROOT" "$T/hub"
check 'スキル更新で二重ネストしない' bash -c '. "$1/lib/common.sh"; copy_skills "$2" base && [ -f "$2/.workspaces/base/.claude/skills/alpha/SKILL.md" ] && [ ! -e "$2/.workspaces/base/.claude/skills/alpha/alpha" ]' _ "$ROOT" "$T/hub"
check 'profile json が無ければ従来どおり' bash -c '. "$1/lib/common.sh"; copy_skills "$2" sekkei' _ "$ROOT" "$T/hub"
printf '{"skills":["../beta"]}\n' > "$T/hub/profiles/base.json"
check '不正スキル名を拒否' bash -c '. "$1/lib/common.sh"; ! copy_skills "$2" base && [ ! -e "$2/.workspaces/base/.claude/skills/beta" ]' _ "$ROOT" "$T/hub"
check 'スキル複製失敗時は hub で起動' bash -c '. "$1/lib/common.sh"; [ "$(role_workspace "$2" base)" = "$2" ]' _ "$ROOT" "$T/hub"
printf '{"skills":["beta"]}\n' > "$T/hub/profiles/sekkei.json"
check '役割を変えても別役割のスキルを読まない' bash -c '. "$1/lib/common.sh"; copy_skills "$2" sekkei && [ -f "$2/.workspaces/sekkei/.claude/skills/beta/SKILL.md" ] && [ ! -e "$2/.workspaces/sekkei/.claude/skills/alpha" ]' _ "$ROOT" "$T/hub"
mkdir -p "$HOME/daimaru-skills/.git" "$HOME/daimaru-skills/profiles" "$HOME/daimaru-skills/.claude/skills/alpha" "$HOME/.config/gws"
printf 'x' > "$HOME/daimaru-skills/.gitmodules"
printf '{"skills":["alpha"]}\n' > "$HOME/daimaru-skills/profiles/base.json"
printf 'a' > "$HOME/daimaru-skills/.claude/skills/alpha/SKILL.md"
cp "$ROOT/tests/stubs/op" "$T/bin/op"; chmod +x "$T/bin/op"
printf 'stale' > "$HOME/.config/gws/.client_secret-old"
printf 'stale' > "$HOME/.config/gws/.op-error.tmp"
printf '#!/bin/sh\nprintf "gh %%s\\n" "$*" >> "$K_CALL_LOG"\n' > "$T/bin/gh"
printf '#!/bin/sh\nprintf "git %%s\\n" "$*" >> "$K_CALL_LOG"\n[ "${K_GIT_PULL_FAIL:-0}" = 1 ] && [ "$1" = pull ] && exit 1\n' > "$T/bin/git"
printf '#!/bin/sh\nif [ "$1" = auth ]; then exit 0; fi\npwd >> "$K_CLAUDE_LOG"\n' > "$T/bin/claude"
chmod +x "$T/bin/gh" "$T/bin/git" "$T/bin/claude"
export K_CALL_LOG="$T/calls.log" K_CLAUDE_LOG="$T/claude.log"
: > "$K_CALL_LOG"; : > "$K_CLAUDE_LOG"
DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/setup.sh" >"$T/setup-run.log" 2>&1
check '認証済み gh でも setup-git を毎回実行' grep -qFx 'gh auth setup-git' "$K_CALL_LOG"
check '通常再実行で hub を fast-forward 更新' grep -qFx 'git pull --ff-only' "$K_CALL_LOG"
out="$(K_GIT_PULL_FAIL=1 DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/setup.sh" 2>&1)"
check 'hub 更新に失敗しても警告して起動する' bash -c '[[ "$1" == *"daimaru-skills を更新できませんでした"* ]] && [ -s "$2" ]' _ "$out" "$K_CLAUDE_LOG"
check '既存 hub の submodule を通常再実行で初期化' grep -qFx 'git submodule update --init --recursive' "$K_CALL_LOG"
check 'Claude を役割ワークスペースで起動' bash -c '[ "$(cd "$1" && pwd -P)" = "$(cd "$2" && pwd -P)" ]' _ "$HOME/daimaru-skills/.workspaces/base" "$(tail -1 "$K_CLAUDE_LOG")"
check '起動時に古い秘密一時ファイルを掃除' bash -c '[ ! -e "$1/.client_secret-old" ] && [ ! -e "$1/.op-error.tmp" ]' _ "$HOME/.config/gws"
mkdir -p "$HOME/.claude/skills/op-secrets/scripts"
: > "$HOME/.claude/skills/op-secrets/scripts/op-doctor.sh"
printf '#!/bin/sh\nprintf "gws %%s\\n" "$*" >> "$K_CALL_LOG"\n' > "$T/bin/gws"
chmod +x "$T/bin/gws"
check '古い Drive 認可だけを state に記録' bash -c '. "$1/lib/common.sh"; K_ROLE=yochi; state_set_scopes drive' _ "$ROOT"
: > "$K_CALL_LOG"
DAIMARU_ROLE=yochi DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/setup.sh" >"$T/yochi-run.log" 2>&1
check '追加スコープが必要なら gws に再ログイン' grep -qFx 'gws auth login -s gmail,drive' "$K_CALL_LOG"
check 'gws 認可成功後にスコープを state へ保存' bash -c '. "$1/lib/common.sh"; scopes_cover "$(state_scopes)" gmail,drive' _ "$ROOT"
: > "$K_CALL_LOG"
DAIMARU_UPDATE=1 bash "$ROOT/setup.sh" >"$T/update-run.log" 2>&1
check 'DAIMARU_UPDATE の役割は保存済みの役割' grep -q '用地 の準備' "$T/update-run.log"
check '更新だけの再実行でも gh setup-git' grep -qFx 'gh auth setup-git' "$K_CALL_LOG"
mkdir -p "$HOME/Downloads"
printf 'FAKE_SECRET_MUST_NOT_PRINT' > "$HOME/Downloads/client_secret-test.json"
out="$(DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/doctor/doctor.sh" 2>&1)"; rc=$?
last="$(printf '%s\n' "$out" | tail -1)"
if [[ "$last" =~ ^DAIMARU_DOCTOR:\ (PASS|FAIL\ missing=[a-z0-9,-]+)$ ]] && { [ "$rc" = 0 ] || [ "$rc" = 2 ]; }; then pass 'doctor 最終行と終了コード'; else fail 'doctor 最終行と終了コード'; fi
if [[ "$out" != *FAKE_SECRET_MUST_NOT_PRINT* ]]; then pass 'doctor は秘密の中身を出さない'; else fail 'doctor は秘密の中身を出さない'; fi
out="$(DAIMARU_ROLE=togo DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/doctor/doctor.sh" 2>&1)"
check 'togo は clasp ログインと proxy の不足を列挙' bash -c '[[ "$1" == *"missing="* ]] && [[ "$1" == *"clasp-login"* ]] && [[ "$1" == *"cloud-sql-proxy"* ]]' _ "$out"
check 'doctor は役割に足りない gws スコープを列挙' contains "$out" gws-scopes
check 'スコープ不足の案内は setup の再実行' contains "$out" 'DAIMARU_ROLE=togo を指定して setup.sh を再実行'
mkdir -p "$HOME/.local/bin"
cp "$T/bin/gws" "$HOME/.local/bin/gws"
out="$(PATH=/usr/bin:/bin DAIMARU_ROLE=togo DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/doctor/doctor.sh" 2>&1)"
check 'doctor 単体でもローカル bin を PATH に補う' contains "$out" 'PATH: gws'
out="$(HOME="$T/empty-home" DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 bash "$ROOT/doctor/doctor.sh" 2>&1)"
check '通信省略でも hub の存在を検査' contains "$out" 'daimaru-skills が見つかりません'
out="$(DAIMARU_ROLE=base bash "$ROOT/doctor/doctor.sh" 2>&1)"
check 'hub の更新確認失敗は警告' bash -c '[[ "$1" == *"更新が必要か確認できません"* && "$1" != *"missing=hub-update"* ]]' _ "$out"
check '不正な配布 URL を拒否' bash -c 'DAIMARU_SETUP_BASE=http://example.invalid DAIMARU_DRY_RUN=1 bash "$1/setup.sh" >/dev/null 2>&1; [ $? = 2 ]' _ "$ROOT"
check 'file URL はテスト指定時だけ許可' bash -c 'DAIMARU_SETUP_BASE=file:///tmp DAIMARU_DRY_RUN=1 bash "$1/setup.sh" >/dev/null 2>&1; [ $? = 2 ] && DAIMARU_SETUP_ALLOW_FILE=1 DAIMARU_SETUP_BASE=file:///tmp DAIMARU_DRY_RUN=1 bash "$1/setup.sh" >/dev/null 2>&1' _ "$ROOT"
out="$(cd "$T" && PATH="${PATH#"$T/bin:"}" DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 DAIMARU_SETUP_ALLOW_FILE=1 DAIMARU_SETUP_BASE="file://$ROOT" bash < "$ROOT/doctor/doctor.sh" 2>&1)"; rc=$?
if { [ "$rc" = 0 ] || [ "$rc" = 2 ]; } && [[ "$out" == *'daimaru-setup 診断'* ]] && [[ "$out" == *'DAIMARU_DOCTOR:'* ]]; then pass 'doctor は pipe 単独実行で共通部品を取得'; else fail 'doctor は pipe 単独実行で共通部品を取得'; fi
mkdir -p "$T/pipe-cwd/lib" "$T/pipe-cwd/profiles"
cp "$ROOT/lib/common.sh" "$T/pipe-cwd/lib/common.sh"
cp "$ROOT/profiles/base.env" "$T/pipe-cwd/profiles/base.env"
out="$(cd "$T/pipe-cwd" && DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 DAIMARU_SETUP_ALLOW_FILE=1 DAIMARU_SETUP_BASE=file:///nonexistent bash < "$ROOT/doctor/doctor.sh" 2>&1)"; rc=$?
if { [ "$rc" = 0 ] || [ "$rc" = 2 ]; } && [[ "$out" == *'daimaru-setup 診断'* ]]; then pass 'doctor の pipe 実行は現在ディレクトリを基準にする'; else fail 'doctor の pipe 実行は現在ディレクトリを基準にする'; fi
check 'pipe 実行の stderr に unbound がない' bash -c 'cd "$1"; DAIMARU_DRY_RUN=1 bash < "$2/setup.sh" 2>"$1/setup.err" >/dev/null; DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 DAIMARU_SETUP_ALLOW_FILE=1 DAIMARU_SETUP_BASE="file://$2" bash < "$2/doctor/doctor.sh" 2>"$1/doctor.err" >/dev/null; ! grep -Ei "unbound|BASH_SOURCE" "$1/setup.err" "$1/doctor.err"' _ "$T" "$ROOT"
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
  done < <(find "$ROOT" -path "$ROOT/.cross-review-tmp" -prune -o -name '*.ps1' -type f -print)
  check 'PS5.1 の CP932 と UTF8 専用経路を全 ps1 で判定' env K_SOURCE_ROOT="$ROOT" pwsh -NoProfile -Command '
    $utfOnly=@("setup.ps1","doctor/doctor.ps1","scripts/op/setup.ps1","scripts/op/sa-token.ps1","scripts/keiri/onboard.ps1")
    $cp=[Text.Encoding]::GetEncoding(932)
    foreach($f in Get-ChildItem $env:K_SOURCE_ROOT -Filter *.ps1 -Recurse | Where-Object { $_.FullName -notlike "*/.cross-review-tmp/*" }) {
      $rel=$f.FullName.Substring($env:K_SOURCE_ROOT.Length+1).Replace("\", "/")
      $bytes=[IO.File]::ReadAllBytes($f.FullName)
      $bom=$bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
      if ($bom) { continue }
      $e=$null; [System.Management.Automation.Language.Parser]::ParseInput($cp.GetString($bytes),[ref]$null,[ref]$e) | Out-Null
      if ($e.Count -gt 0 -and $utfOnly -notcontains $rel) { Write-Host "$rel requires a UTF8 execution route"; exit 1 }
    }
    $setup=[IO.File]::ReadAllText((Join-Path $env:K_SOURCE_ROOT "setup.ps1"),[Text.Encoding]::UTF8)
    if ($setup -notmatch "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command" -or $setup -notmatch "DAIMARU_DOCTOR_FILE" -or $setup -notmatch "ReadAllText") { exit 1 }
  '
  check 'PowerShell Run-Step は出力の後の false を失敗とする' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" pwsh -NoProfile -Command '. $env:K_COMMON_FILE; $script:KRole="base"; Run-Step noisy { return $false } { Write-Output "noise"; return $false }; if ((Get-StateStep noisy) -ne "fail") { exit 1 }'
  check 'PowerShell の新環境 DRY_RUN は base を選ぶ' env APPDATA="$T/fresh-appdata" DAIMARU_DRY_RUN=1 DAIMARU_ROLE='' K_SETUP_FILE="$ROOT/setup.ps1" pwsh -NoProfile -Command 'iex ([IO.File]::ReadAllText($env:K_SETUP_FILE,[Text.Encoding]::UTF8)); if ($role -ne "base") { exit 1 }'
  check 'PowerShell 共有 OAuth の破損は既存値を守り一時ファイルを消す' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_TEST_SECRET="$T/ps-client_secret.json" pwsh -NoProfile -Command '
    . $env:K_COMMON_FILE
    function Set-PrivateAcl([string]$Path,[bool]$Directory) { return $true }
    if (-not (Install-GwsSecret $env:K_TEST_SECRET)) { exit 1 }
    if ([IO.File]::ReadAllText($env:OP_STUB_LOG) -notmatch "SA=0 ARGS=--account team.1password.com read") { exit 5 }
    $before=[IO.File]::ReadAllText($env:K_TEST_SECRET)
    $env:OP_STUB_READ_VALUE="broken"
    if (Install-GwsSecret $env:K_TEST_SECRET) { exit 2 }
    if ([IO.File]::ReadAllText($env:K_TEST_SECRET) -ne $before) { exit 3 }
    $dir=Split-Path $env:K_TEST_SECRET -Parent
    if (@(Get-ChildItem $dir -Force | Where-Object { $_.Name -like ".client_secret-*" -or $_.Name -eq ".op-error.tmp" }).Count) { exit 4 }
  '
  check 'PowerShell サービスアカウントは account 指定を省く' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_TEST_SECRET="$T/ps-client_secret.json" pwsh -NoProfile -Command '
    . $env:K_COMMON_FILE
    function Set-PrivateAcl([string]$Path,[bool]$Directory) { return $true }
    $env:OP_SERVICE_ACCOUNT_TOKEN="test"
    if (-not (Install-GwsSecret $env:K_TEST_SECRET)) { exit 1 }
    if ([IO.File]::ReadAllText($env:OP_STUB_LOG) -notmatch "SA=1 ARGS=read") { exit 2 }
  '
  check 'PowerShell スキル更新は二重ネストしない' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_TEST_HUB="$T/hub" pwsh -NoProfile -Command '$ErrorActionPreference="Stop"; . $env:K_COMMON_FILE; if (-not (Copy-RoleSkills $env:K_TEST_HUB base)) { exit 1 }; $w=Get-RoleWorkspace $env:K_TEST_HUB base; if (-not (Test-Path (Join-Path $w ".claude/skills/alpha/SKILL.md")) -or (Test-Path (Join-Path $w ".claude/skills/alpha/alpha")) -or (Test-Path (Join-Path $w ".claude/skills/beta"))) { exit 1 }'
  check 'PowerShell ワークスペースで hub 文書と repos が見える' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_TEST_HUB="$T/hub" pwsh -NoProfile -Command '. $env:K_COMMON_FILE; $w=Get-RoleWorkspace $env:K_TEST_HUB base; if (-not (Test-Path (Join-Path $w "CLAUDE.md")) -or -not (Test-Path (Join-Path $w "repos/demo/readme")) -or -not (Test-Path (Join-Path $env:K_TEST_HUB ".git/info/exclude"))) { exit 1 }'
  check 'PowerShell スキル複製失敗時は hub に戻る' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_TEST_HUB="$T/hub" pwsh -NoProfile -Command '. $env:K_COMMON_FILE; $file=Join-Path $env:K_TEST_HUB "profiles/base.json"; try { [IO.File]::WriteAllText($file,"{" + "`"skills`": [`"../bad`"]}"); if (Copy-RoleSkills $env:K_TEST_HUB base) { exit 1 }; if ((Get-RoleWorkspace $env:K_TEST_HUB base) -ne $env:K_TEST_HUB) { exit 2 } } finally { [IO.File]::WriteAllText($file,"{" + "`"skills`": [`"alpha`"]}") }'
  check 'PowerShell 5.1 用 gws JSON エスケープ' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_EXPECTED_GWS='{\"pageSize\":1,\"fields\":\"files(id)\"}' pwsh -NoProfile -Command '. $env:K_COMMON_FILE; $PSVersionTable.PSVersion=[version]"5.1"; function Invoke-Cli([string]$Name,[string[]]$CliArgs) { $CliArgs[-1] }; if ((Invoke-Gws @("drive","files","list")) -cne $env:K_EXPECTED_GWS) { exit 1 }'
  printf '\357\273\277Write-Output "UTF8"\n' > "$T/remote.ps1"
  check 'PowerShell の再取得コードは先頭 BOM を除く' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_REMOTE_FILE="file://$T/remote.ps1" pwsh -NoProfile -Command '. $env:K_COMMON_FILE; $code=Get-RemoteScript $env:K_REMOTE_FILE; if ($code[0] -eq [char]0xFEFF -or (Invoke-Expression $code) -ne "UTF8") { exit 1 }'
  out="$(APPDATA="$T/appdata" DAIMARU_SETUP_ROOT='' DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 K_SOURCE_ROOT="$ROOT" K_DOCTOR_FILE="$ROOT/doctor/doctor.ps1" pwsh -NoProfile -Command 'function Invoke-WebRequest { param([string]$Uri,[string]$OutFile,[switch]$UseBasicParsing) $rel=if ($Uri -match "/lib/common.ps1$") { "lib/common.ps1" } elseif ($Uri -match "/profiles/base.env$") { "profiles/base.env" } else { throw "unexpected URL" }; Copy-Item (Join-Path $env:K_SOURCE_ROOT $rel) $OutFile }; Invoke-Expression ([IO.File]::ReadAllText($env:K_DOCTOR_FILE,[Text.Encoding]::UTF8))' 2>&1)"; rc=$?
  if { [ "$rc" = 0 ] || [ "$rc" = 2 ]; } && [[ "$out" == *'daimaru-setup 診断'* ]] && [[ "$out" == *'DAIMARU_DOCTOR:'* ]]; then pass 'PowerShell doctor は iex 単独実行で共通部品を取得'; else fail 'PowerShell doctor は iex 単独実行で共通部品を取得'; fi
  out="$(APPDATA="$T/appdata" DAIMARU_SETUP_ROOT="$ROOT" DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 K_DOCTOR_FILE="$ROOT/doctor/doctor.ps1" pwsh -NoProfile -Command '$s=[IO.File]::ReadAllText($env:K_DOCTOR_FILE,[Text.Encoding]::UTF8); iex $s; iex $s; Write-Output HOST_ALIVE' 2>&1)"
  check 'PowerShell doctor の iex を2回呼んでもホストが続く' bash -c '[[ "$1" == *HOST_ALIVE* ]] && [ "$(printf "%s\n" "$1" | grep -c DAIMARU_DOCTOR:)" = 2 ]' _ "$out"
  APPDATA="$T/appdata" DAIMARU_SETUP_ROOT="$ROOT" DAIMARU_ROLE=invalid pwsh -NoProfile -File "$ROOT/doctor/doctor.ps1" >/dev/null 2>&1; rc=$?
  check 'PowerShell doctor の -File は終了コード 2' [ "$rc" = 2 ]
  APPDATA="$T/appdata" DAIMARU_SETUP_BASE=http://example.invalid pwsh -NoProfile -File "$ROOT/doctor/doctor.ps1" >/dev/null 2>&1; rc=$?
  check 'PowerShell doctor の早期失敗も -File は終了コード 2' [ "$rc" = 2 ]
  out="$(APPDATA="$T/appdata" DAIMARU_SETUP_BASE=http://example.invalid K_DOCTOR_FILE="$ROOT/doctor/doctor.ps1" pwsh -NoProfile -Command 'iex ([IO.File]::ReadAllText($env:K_DOCTOR_FILE,[Text.Encoding]::UTF8)); Write-Output HOST_ALIVE' 2>&1)"; rc=$?
  check 'PowerShell doctor の早期失敗でも iex 呼び出し元は生存' bash -c '[[ "$1" == *HOST_ALIVE* && "$1" == *"DAIMARU_DOCTOR: FAIL missing=base"* ]] && [ "$2" = 0 ]' _ "$out" "$rc"
  check 'PowerShell setup の早期 return で一時ディレクトリを消す' env APPDATA="$T/appdata" DAIMARU_DRY_RUN='' K_SETUP_FILE="$ROOT/setup.ps1" pwsh -NoProfile -Command 'function Invoke-WebRequest { throw "offline" }; iex ([IO.File]::ReadAllText($env:K_SETUP_FILE,[Text.Encoding]::UTF8)); if (-not $script:KTemp -or (Test-Path $script:KTemp)) { exit 1 }'
  check 'PowerShell doctor の早期 return で一時ディレクトリを消す' env APPDATA="$T/appdata" DAIMARU_SETUP_ROOT="$T/no-root" K_DOCTOR_FILE="$ROOT/doctor/doctor.ps1" pwsh -NoProfile -Command 'function Invoke-WebRequest { throw "offline" }; iex ([IO.File]::ReadAllText($env:K_DOCTOR_FILE,[Text.Encoding]::UTF8)); if (-not $script:DoctorTemp -or (Test-Path $script:DoctorTemp)) { exit 1 }'
  check 'PowerShell doctor は単体で PATH を更新' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" K_DOCTOR_FILE="$ROOT/doctor/doctor.ps1" pwsh -NoProfile -Command '$s=[IO.File]::ReadAllText($env:K_DOCTOR_FILE,[Text.Encoding]::UTF8); if ($s -notmatch "Refresh-Path") { exit 1 }; . $env:K_COMMON_FILE; $old=$env:Path; Refresh-Path; if ($env:OS -ne "Windows_NT" -and $env:Path -ne $old) { exit 1 }'
  out="$(HOME="$T/empty-home" APPDATA="$T/appdata" DAIMARU_SETUP_ROOT="$ROOT" DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 pwsh -NoProfile -File "$ROOT/doctor/doctor.ps1" 2>&1)"
  check 'PowerShell doctor も通信省略中に hub の存在を検査' contains "$out" 'daimaru-skills が見つかりません'
  check 'PowerShell 通常再実行は ff-only、更新不足は警告' bash -c 'grep -qF "git pull --ff-only" "$1" && grep -qF "Warn '\''daimaru-skills は更新が必要か確認できません'\''" "$2"' _ "$ROOT/setup.ps1" "$ROOT/doctor/doctor.ps1"
  check 'PowerShell 保存済み役割と追加スコープを判定' env APPDATA="$T/appdata" K_COMMON_FILE="$ROOT/lib/common.ps1" pwsh -NoProfile -Command '. $env:K_COMMON_FILE; $script:KRole="togo"; Set-StateScopes "drive,gmail"; Remove-Item Env:DAIMARU_ROLE -ErrorAction SilentlyContinue; if (-not (Select-Role) -or $script:KRole -ne "togo" -or (Test-Scopes (Get-StateScopes) "drive,gmail,calendar")) { exit 1 }'
  out="$(APPDATA="$T/appdata" DAIMARU_DRY_RUN=1 DAIMARU_ROLE='' pwsh -NoProfile -File "$ROOT/setup.ps1" 2>&1)"
  check 'PowerShell の再実行は保存済み役割を使用' contains "$out" '統合 の準備'
  : > "$K_CALL_LOG"
  APPDATA="$T/appdata" DAIMARU_ROLE=base DAIMARU_UPDATE=1 pwsh -NoProfile -File "$ROOT/setup.ps1" >"$T/ps-update.log" 2>&1
  check 'PowerShell 更新時も gh setup-git' grep -qFx 'gh auth setup-git' "$K_CALL_LOG"
  out="$(APPDATA="$T/appdata" OS=Windows_NT DAIMARU_DRY_RUN=1 K_SETUP_FILE="$ROOT/setup.ps1" pwsh -NoProfile -Command 'function Set-ExecutionPolicy { throw "blocked" }; iex ([IO.File]::ReadAllText($env:K_SETUP_FILE,[Text.Encoding]::UTF8)); Write-Output HOST_ALIVE' 2>&1)"
  check 'PowerShell 実行ポリシー変更失敗後も setup が続く' bash -c '[[ "$1" == *HOST_ALIVE* && "$1" == *"予定: "* ]]' _ "$out"
  out="$(APPDATA="$T/appdata" OS=Windows_NT DAIMARU_SETUP_ROOT="$ROOT" DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 K_DOCTOR_FILE="$ROOT/doctor/doctor.ps1" pwsh -NoProfile -Command 'function Set-ExecutionPolicy { throw "blocked" }; iex ([IO.File]::ReadAllText($env:K_DOCTOR_FILE,[Text.Encoding]::UTF8)); Write-Output HOST_ALIVE' 2>&1)"
  check 'PowerShell 実行ポリシー変更失敗後も doctor が続く' bash -c '[[ "$1" == *HOST_ALIVE* && "$1" == *DAIMARU_DOCTOR:* ]]' _ "$out"
fi
for file in "$ROOT/setup.ps1" "$ROOT/doctor/doctor.ps1"; do
  check "iex 用は BOM なし・CRLF ${file#"$ROOT"/}" node -e 'const b=require("fs").readFileSync(process.argv[1]);process.exit(b.subarray(0,3).equals(Buffer.from([239,187,191]))||!b.includes(Buffer.from("\r\n"))||b.toString().replace(/\r\n/g,"").includes("\n")?1:0)' "$file"
done
check 'dot-source 専用 common.ps1 は BOM あり・CRLF' node -e 'const b=require("fs").readFileSync(process.argv[1]);process.exit(!b.subarray(0,3).equals(Buffer.from([239,187,191]))||!b.includes(Buffer.from("\r\n"))?1:0)' "$ROOT/lib/common.ps1"
cat > "$T/bin/curl" <<'STUB'
#!/bin/sh
url=''; out=''
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2;; -*) shift;; *) url="$1"; shift;; esac
done
case "$url" in file://*) cp "${url#file://}" "$out";; *) exit 77;; esac
STUB
chmod +x "$T/bin/curl"
mkdir -p "$T/setup-tmp"
out="$(cd "$T" && TMPDIR="$T/setup-tmp" DAIMARU_SETUP_BASE="file://$ROOT" DAIMARU_SETUP_ALLOW_FILE=1 DAIMARU_ROLE=base DAIMARU_DOCTOR_SKIP_NETWORK=1 bash < "$ROOT/setup.sh" 2>&1)"; rc=$?
check 'pipe setup は Claude 起動前に一時ディレクトリを消す' bash -c '[ "$1" = 0 ] && [ -z "$(find "$2" -mindepth 1 -maxdepth 1 -print -quit)" ] && [[ "$3" != *"共通部品を取得できません"* ]]' _ "$rc" "$T/setup-tmp" "$out"
printf 'kitting: %s pass / %s fail\n' "$pass_n" "$fail_n"
[ "$fail_n" = 0 ]
