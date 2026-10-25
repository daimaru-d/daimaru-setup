#!/usr/bin/env bash
# =============================================================================
# op-secrets のスクリプトのテスト。実行: bash tests/scripts.test.sh
# - 本物の op・キーチェーン・~/.claude/settings.json には触らない
#   （HOME を一時ディレクトリに向け、PATH の先頭に tests/stubs/op を置く）
# - 偽の秘密の値 FAKE_SECRET が、引数（スタブの記録）・画面に出ないことを確かめる
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/skills/op-secrets/scripts"
PASS_N=0; FAIL_N=0
pass(){ PASS_N=$((PASS_N + 1)); printf 'ok   %s\n' "$1"; }
fail(){ FAIL_N=$((FAIL_N + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; }
check(){ local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
contains(){ case "$1" in *"$2"*) return 0;; esac; return 1; }
not_contains(){ ! contains "$1" "$2"; }

T="$(mktemp -d "${TMPDIR:-/tmp}/op-secrets-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export USERPROFILE="$HOME"
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export OP_STUB_LOG="$T/op.log"; : > "$OP_STUB_LOG"
export OP_STUB_DIR="$T/stub"; mkdir -p "$OP_STUB_DIR"
export PATH="$ROOT/tests/stubs:$PATH"
export DAIMARU_OP_SA_BACKEND=file
unset OP_ACCOUNT OP_VAULT OP_ENV_FILE OP_SA_MODE OP_SERVICE_ACCOUNT_TOKEN OP_STUB_WHOAMI_RC OP_STUB_VERSION OP_STUB_ITEM_EXISTS
FAKE_SECRET='FAKE-S3cr3t-Value-for-test'
FAKE_USER='someone@example.com'
reset_stub(){ : > "$OP_STUB_LOG"; rm -f "$OP_STUB_DIR"/template-*.json; }
tmp_clean(){ [ -z "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 ! -name xcrun_db -print -quit)" ]; }

echo "== 構文"
SH_FILES=("$S"/*.sh "$ROOT/scripts/op/setup.sh" "$ROOT/scripts/op/sa-token.sh" "$ROOT/tests/scripts.test.sh" "$ROOT/tests/stubs/op" "$ROOT/setup.sh")
for f in "${SH_FILES[@]}"; do check "bash -n ${f#"$ROOT"/}" bash -n "$f"; done
if command -v /bin/bash >/dev/null && /bin/bash --version | head -1 | grep -q 'version 3'; then
  for f in "$S"/*.sh "$ROOT/scripts/op/setup.sh" "$ROOT/scripts/op/sa-token.sh"; do check "bash 3.2 -n ${f#"$ROOT"/}" /bin/bash -n "$f"; done
fi
if command -v shellcheck >/dev/null 2>&1; then
  # 既存の setup.sh は対象外（今回の追記以外の既存の警告があるため）
  for f in "$S"/*.sh "$ROOT/scripts/op/setup.sh" "$ROOT/scripts/op/sa-token.sh" "$ROOT/tests/scripts.test.sh" "$ROOT/tests/stubs/op"; do
    check "shellcheck ${f#"$ROOT"/}" shellcheck -S warning -x -P "$S" "$f"
  done
else
  echo "（shellcheck が無いため省略）"
fi
for f in "$S"/*.js "$ROOT"/tests/*.js; do check "node --check ${f#"$ROOT"/}" node --check "$f"; done
for f in setup.ps1 sa-token.ps1; do
  check "scripts/op/$f は BOM なし（irm | iex 用）" bash -c "[ \"\$(head -c 3 '$ROOT/scripts/op/$f' | od -An -tx1 | tr -d ' ')\" != efbbbf ]"
done
for f in "$ROOT/setup.ps1" "$ROOT/doctor/doctor.ps1"; do
  check "${f#"$ROOT"/} は BOM なし（irm | iex 用）" bash -c '[ "$(head -c 3 "$1" | od -An -tx1 | tr -d " ")" != efbbbf ]' _ "$f"
done
check 'lib/common.ps1 は BOM あり（ディスクから dot-source）' bash -c '[ "$(head -c 3 "$1" | od -An -tx1 | tr -d " ")" = efbbbf ]' _ "$ROOT/lib/common.ps1"
# .gitattributes と実ファイルを直接確認し、テスト中に Git を呼ばない。
check '.gitattributes: sh と stub は eol=lf' bash -c 'grep -qxF "*.sh text eol=lf" "$1/.gitattributes" && grep -qxF "tests/stubs/op text eol=lf" "$1/.gitattributes"' _ "$ROOT"
check '.gitattributes: ps1 は eol=crlf' grep -qxF '*.ps1 text eol=crlf' "$ROOT/.gitattributes"
check '配布 sh と stub の実ファイルは LF' node -e 'const fs=require("fs");for(const p of process.argv.slice(1)){if(fs.readFileSync(p).includes(Buffer.from("\r")))process.exit(1)}' "$ROOT/setup.sh" "$ROOT/doctor/doctor.sh" "$ROOT/lib/common.sh" "$ROOT/tests/stubs/op"

echo "== lib.sh"
(
  # shellcheck source=../skills/op-secrets/scripts/lib.sh
  . "$S/lib.sh"
  ops_valid_item_name andpad && ops_valid_item_name kintone-keiri && ops_valid_item_name 9a \
    && ! ops_valid_item_name Andpad && ! ops_valid_item_name -x && ! ops_valid_item_name 'a b' \
    && ! ops_valid_item_name 'アンドパッド' && ! ops_valid_item_name '' && ! ops_valid_item_name 'a_b'
) && pass "項目名の検証" || fail "項目名の検証"
(
  . "$S/lib.sh"
  [ "$(ops_var_prefix andpad-browser)" = ANDPAD_BROWSER ] && ops_is_secret_key api_key && ops_is_secret_key DB_PASS \
    && ops_is_secret_key ANDPAD_PASSWORD && ops_is_secret_key CLIENT_SECRET && ops_is_secret_key KEY \
    && ! ops_is_secret_key DRY_RUN && ! ops_is_secret_key BYPASS_CACHE && ! ops_is_secret_key MONKEY_PATH && ! ops_is_secret_key KEYBOARD
) && pass "変数名の生成・秘密キーの判定" || fail "変数名の生成・秘密キーの判定"
(
  . "$S/lib.sh"
  ops_parse_env_line '  export FOO = "bar baz"  ' && [ "$OPS_K" = FOO ] && [ "$OPS_V" = 'bar baz' ] \
    && ops_parse_env_line "X=1 # comment" && [ "$OPS_V" = 1 ] \
    && { ops_parse_env_line '# c'; [ $? = 1 ]; } && { ops_parse_env_line 'not a line'; [ $? = 2 ]; }
) && pass ".env 行の分解" || fail ".env 行の分解"
(
  mkdir -p "$HOME/.config/daimaru-op"; printf 'OP_VAULT=FromFile\nOP_ACCOUNT=$(touch %s/pwned)\n' "$T" > "$HOME/.config/daimaru-op/config"
  . "$S/lib.sh"; OP_VAULT=FromEnv; ops_load_config
  [ "$OP_VAULT" = FromEnv ] && [ "$OP_ENV_FILE" = .env.op ] && [ ! -e "$T/pwned" ]
) && pass "設定: 環境変数が優先・設定ファイルを実行しない" || fail "設定: 環境変数が優先・設定ファイルを実行しない"
rm -f "$HOME/.config/daimaru-op/config"

echo "== settings-merge.js"
SET="$T/settings/settings.json"; mkdir -p "$(dirname "$SET")"
printf '{\n  "model": "x",\n  "permissions": { "allow": ["Bash(ls:*)"], "deny": ["Read(**/.env)"] },\n  "hooks": { "PreToolUse": [ { "matcher": "Edit", "hooks": [ { "type": "command", "command": "echo hi" } ] } ] }\n}\n' > "$SET"
node "$S/settings-merge.js" --settings "$SET" >/dev/null; rc=$?
check "1回目は成功" [ "$rc" = 0 ]
h1="$(node -e 'const s=require(process.argv[1]); console.log(JSON.stringify(s))' "$SET")"
node "$S/settings-merge.js" --settings "$SET" >/dev/null
h2="$(node -e 'const s=require(process.argv[1]); console.log(JSON.stringify(s))' "$SET")"
check "2回目で変わらない（冪等）" [ "$h1" = "$h2" ]
check "バックアップは 1 つ" [ "$(find "$(dirname "$SET")" -name 'settings.json.bak-*' | wc -l | tr -d ' ')" = 1 ]
check "既存の設定を残す" node -e '
  const s=require(process.argv[1]); const ok = s.model==="x" && s.permissions.allow[0]==="Bash(ls:*)"
    && s.hooks.PreToolUse[0].matcher==="Edit" && s.hooks.PreToolUse.length===2
    && s.permissions.deny.filter(d=>d==="Read(**/.env)").length===1 && s.permissions.deny.length===16
    && s.permissions.deny.includes("Bash(op inject:*)") && s.permissions.deny.includes("Bash(op run:*)")
    && !s.permissions.deny.includes("Read(**/.env.op)") && s.hooks.PreToolUse[1].matcher==="Bash|PowerShell";
  process.exit(ok?0:1)' "$SET"
check "フックの command は HOME の絶対パス" node -e '
  const s=require(process.argv[1]); const c=s.hooks.PreToolUse[1].hooks[0].command;
  process.exit(c===`node "${process.argv[2]}/.claude/skills/op-secrets/scripts/op-guard.js"` ? 0 : 1)' "$SET" "$HOME"
out="$(node "$S/settings-merge.js" --check --settings "$SET" 2>&1)"; rc=$?
check "--check: 見張りの本体が無ければ 2" [ "$rc" = 2 ]
check "--check: 何が無いかを出す" contains "$out" "見張りの本体"
# 古い matcher（Bash だけ）の登録は Bash|PowerShell に直す
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"node \\"%s/.claude/skills/op-secrets/scripts/op-guard.js\\""}]}]}}\n' "$HOME" > "$T/settings/old.json"
node "$S/settings-merge.js" --settings "$T/settings/old.json" >/dev/null
check "古い matcher を Bash|PowerShell に直す（足さない）" node -e '
  const s=require(process.argv[1]); process.exit(s.hooks.PreToolUse.length===1 && s.hooks.PreToolUse[0].matcher==="Bash|PowerShell" ? 0 : 1)' "$T/settings/old.json"
# --skill-dir: 実際に置いた場所でフックを登録する
node "$S/settings-merge.js" --settings "$T/settings/skilldir.json" --skill-dir "$T/elsewhere/op-secrets" >/dev/null
check "--skill-dir の場所でフックを登録" grep -qF "$T/elsewhere/op-secrets/scripts/op-guard.js" "$T/settings/skilldir.json"
# シンボリックリンクの settings.json はリンクのまま実体に書く
mkdir -p "$T/dotfiles"; printf '{"model":"y"}\n' > "$T/dotfiles/settings.json"; ln -s "$T/dotfiles/settings.json" "$T/settings/link.json"
node "$S/settings-merge.js" --settings "$T/settings/link.json" >/dev/null
check "シンボリックリンクを壊さない" bash -c "[ -L '$T/settings/link.json' ] && grep -q 'op-guard.js' '$T/dotfiles/settings.json' && grep -q '\"model\": \"y\"' '$T/dotfiles/settings.json'"
printf '{ broken' > "$T/settings/broken.json"
node "$S/settings-merge.js" --settings "$T/settings/broken.json" >/dev/null 2>&1; rc=$?
check "壊れた JSON は触らずに 2" [ "$rc" = 2 ]
check "壊れた JSON は中身そのまま・バックアップなし" bash -c "[ \"\$(cat '$T/settings/broken.json')\" = '{ broken' ] && ! ls '$T/settings/broken.json.bak-'* >/dev/null 2>&1"

echo "== install.sh（一時 HOME に）"
WORK="$T/work"; mkdir -p "$WORK"
out="$(cd "$WORK" && bash "$S/install.sh" 2>&1)"; rc=$?
check "install は終了コード 0" [ "$rc" = 0 ]
check "スキルをコピー" [ -f "$HOME/.claude/skills/op-secrets/scripts/op-guard.js" ]
check "SKILL.md もコピー" [ -f "$HOME/.claude/skills/op-secrets/SKILL.md" ]
check "設定ファイルを作る" grep -qx 'OP_VAULT=Claude-Automation' "$HOME/.config/daimaru-op/config"
check "診断の最終行を出す" contains "$out" "OP_DOCTOR: PASS"
s1="$(cat "$HOME/.claude/settings.json")"
(cd "$WORK" && bash "$S/install.sh" >/dev/null 2>&1)
check "2回目も同じ settings.json（冪等）" [ "$s1" = "$(cat "$HOME/.claude/settings.json")" ]
check "settings-merge --check が通る" bash -c "node '$S/settings-merge.js' --check >/dev/null"

echo "== op-run.sh"
cd "$WORK" || exit 1
: > x.mjs; : > "a b.mjs"
# 子プロセスの環境を「ある/ない」だけで出す（値は出さない）
printf '#!/usr/bin/env bash\nfor v in OP_SERVICE_ACCOUNT_TOKEN OP_ACCOUNT ANDPAD_PASSWORD; do if [ -n "${!v:-}" ]; then echo "$v=SET"; else echo "$v=UNSET"; fi; done\n' > showenv.sh
printf '# comment\nANDPAD_EMAIL=op://Claude-Automation/andpad/username\nANDPAD_PASSWORD=%s\nDRY_RUN=1\n' "$FAKE_SECRET" > .env.op
reset_stub
out="$(bash "$S/op-run.sh" -- node x.mjs 2>&1)"; rc=$?
check "(a) 平文の秘密らしい行は拒否" [ "$rc" = 2 ]
check "(a) 行番号を出す" contains "$out" "行 3"
check "(a) 値は出さない" not_contains "$out" "$FAKE_SECRET"
check "(a) op は呼ばない" [ ! -s "$OP_STUB_LOG" ]
printf '# 参照だけ\nANDPAD_EMAIL=op://Claude-Automation/andpad/username\nANDPAD_PASSWORD=op://Claude-Automation/andpad/password\nDRY_RUN=1\nEMPTY_TOKEN=\n' > .env.op
for c in env printenv set export /usr/bin/env "env -0" "env -u FOO" "printenv ANDPAD_PASSWORD"; do
  reset_stub
  # shellcheck disable=SC2086  # c は空白で分けて渡す
  bash "$S/op-run.sh" -- $c >/dev/null 2>&1; rc=$?
  check "(b) -- $c は拒否" bash -c '[ "$1" = 2 ] && [ ! -s "$2" ]' _ "$rc" "$OP_STUB_LOG"
done
for c in "sh -c" "bash -c" "node -e" "node -p" "python3 -c" "python -c" "pwsh -Command" "/bin/sh -c"; do
  reset_stub
  # shellcheck disable=SC2086
  out="$(bash "$S/op-run.sh" -- $c 'echo x' 2>&1)"; rc=$?
  check "(e) -- ${c}（その場のスクリプト）は拒否" bash -c '[ "$1" = 2 ] && [ ! -s "$2" ] && [[ "$3" == *"ファイルにして"* ]]' _ "$rc" "$OP_STUB_LOG" "$out"
done
reset_stub; bash "$S/op-run.sh" -- env DRY_RUN=1 node x.mjs >/dev/null 2>&1; rc=$?
check "(e) env の後にコマンドがあれば通す" [ "$rc" = 0 ]
reset_stub; bash "$S/op-run.sh" -- bash showenv.sh >/dev/null 2>&1; rc=$?
check "(e) スクリプトのファイルは通す" [ "$rc" = 0 ]
reset_stub; out="$(bash "$S/op-run.sh" -- node x.mjs 2>&1)"; rc=$?
check "(c) 正常時は 0" [ "$rc" = 0 ]
check "(c) op --account ... run --env-file .env.op -- node x.mjs を呼ぶ" \
  grep -qxF 'SA=0 ARGS=--account daimaruenterprise.1password.com run --env-file .env.op --no-masking=false -- node x.mjs' "$OP_STUB_LOG"
reset_stub; bash "$S/op-run.sh" --env-file=.env.op -- node "a b.mjs" >/dev/null 2>&1
check "(c) --env-file= と空白入りの引数" grep -qF 'run --env-file .env.op --no-masking=false -- node a b.mjs' "$OP_STUB_LOG"
reset_stub; bash "$S/op-run.sh" --env-file missing.env.op -- node x.mjs >/dev/null 2>&1; rc=$?
check "(d) env ファイルが無ければ 2" [ "$rc" = 2 ]
printf 'NOT A VALID LINE\n' > bad.env.op
bash "$S/op-run.sh" --env-file bad.env.op -- node x.mjs >/dev/null 2>&1; rc=$?
check "(d) 形の不正な行は拒否" [ "$rc" = 2 ]

echo "== op-sa-token.sh（file 保管でテスト。キーチェーンには触らない）"
out="$(printf '%s\n' "$FAKE_SECRET" | bash "$S/op-sa-token.sh" set 2>&1)"; rc=$?
if { : < /dev/tty; } 2>/dev/null; then
  echo "（端末があるため、端末なしの set の確認は省略）"
else
  check "端末なしの set は 2 で、人が実行する 1 行を案内" bash -c '[ "$1" = 2 ] && [[ "$2" == *sa-token.ps1* && "$2" == *sa-token.sh* ]]' _ "$rc" "$out"
  check "端末なしの set は保管しない" [ ! -e "$HOME/.config/daimaru-op/sa-token" ]
fi
out="$(printf '%s\n' "$FAKE_SECRET" | OPS_SA_STDIN=1 bash "$S/op-sa-token.sh" set 2>&1)"; rc=$?
check "set は 0" [ "$rc" = 0 ]
check "set は値を出さない" not_contains "$out" "$FAKE_SECRET"
check "保管ファイルは 0600" bash -c "ls -l '$HOME/.config/daimaru-op/sa-token' | grep -q '^-rw-------'"
out="$(bash "$S/op-sa-token.sh" status 2>&1)"
check "status は あり・値を出さない" bash -c '[[ "$1" == *あり* && "$1" != *"$2"* ]]' _ "$out" "$FAKE_SECRET"
bash "$S/op-sa-token.sh" load >/dev/null 2>&1; rc=$?
check "load を直接呼ぶと拒否" [ "$rc" = 2 ]
reset_stub; out="$(bash "$S/op-run.sh" --sa -- node x.mjs 2>&1)"
check "--sa: --account を付けずトークンを op にだけ渡す" grep -qxF 'SA=1 ARGS=run --env-file .env.op --no-masking=false -- env -u OP_SERVICE_ACCOUNT_TOKEN node x.mjs' "$OP_STUB_LOG"
reset_stub; out="$(OP_ACCOUNT=someone.1password.com bash "$S/op-run.sh" --sa -- bash showenv.sh 2>&1)"
check "--sa: 子プロセスにトークンと OP_ACCOUNT を渡さない" bash -c '[[ "$1" == *OP_SERVICE_ACCOUNT_TOKEN=UNSET* && "$1" == *OP_ACCOUNT=UNSET* ]]' _ "$out"
reset_stub; out="$(OP_ACCOUNT=daimaruenterprise.1password.com bash "$S/op-run.sh" -- bash showenv.sh 2>&1)"
check "通常: 子プロセスに OP_ACCOUNT を渡さない" bash -c '[[ "$1" == *OP_ACCOUNT=UNSET* ]]' _ "$out"
check "--sa: 値を出さない" not_contains "$out$(cat "$OP_STUB_LOG")" "$FAKE_SECRET"
bash "$S/op-sa-token.sh" clear >/dev/null 2>&1
out="$(bash "$S/op-sa-token.sh" status 2>&1)"; rc=$?
check "clear 後は なし" bash -c '[[ "$1" == *なし* ]]' _ "$out"

echo "== op-doctor.sh"
rm -f .env.op bad.env.op
out="$(bash "$S/op-doctor.sh" 2>&1)"; rc=$?
check "PASS 行と終了コード 0" bash -c '[ "$1" = 0 ] && [ "$(printf "%s\n" "$2" | tail -1)" = "OP_DOCTOR: PASS" ]' _ "$rc" "$out"
out="$(OP_STUB_WHOAMI_RC=1 bash "$S/op-doctor.sh" 2>&1)"; rc=$?
check "サインイン不可で FAIL missing=2" bash -c '[ "$1" = 2 ] && [ "$(printf "%s\n" "$2" | tail -1)" = "OP_DOCTOR: FAIL missing=2" ]' _ "$rc" "$out"
out="$(OP_STUB_VERSION=1.12.0 OP_STUB_VAULT_RC=1 bash "$S/op-doctor.sh" 2>&1)"
check "古い op・保管庫なしで FAIL missing=1,2,3,4" contains "$(printf '%s\n' "$out" | tail -1)" "OP_DOCTOR: FAIL missing=1,2,3,4"
mkdir -p proj/sub; printf 'A_PASSWORD=%s\nB=op://Claude-Automation/x/y\nC=\n# D=1\n' "$FAKE_SECRET" > proj/sub/.env
printf 'X=1\n' > proj/.env.example
out="$(bash "$S/op-doctor.sh" 2>&1)"; rc=$?
check "平文の .env を警告（値の入った行 1）" contains "$out" "proj/sub/.env（値が入っている行: 1）"
check ".env.example は警告しない" not_contains "$out" ".env.example"
check "警告だけなら PASS" [ "$rc" = 0 ]
check "doctor は値を出さない" not_contains "$out" "$FAKE_SECRET"
rm -rf proj
out="$(OP_SA_MODE=1 bash "$S/op-doctor.sh" 2>&1)"
check "無人実行でトークンなしなら FAIL missing=7" contains "$(printf '%s\n' "$out" | tail -1)" "missing=7"
mv "$HOME/.claude/settings.json" "$T/settings.saved"
out="$(bash "$S/op-doctor.sh" 2>&1)"
check "見張りが無ければ FAIL missing=5" contains "$(printf '%s\n' "$out" | tail -1)" "missing=5"
mv "$T/settings.saved" "$HOME/.claude/settings.json"
printf 'A_PASSWORD=x\n' > "$HOME/.env"
out="$(cd "$HOME" && bash "$S/op-doctor.sh" 2>&1)"
check "ホームフォルダでは .env の検査を省略" bash -c '[[ "$1" == *"検査を省略"* && "$1" != *"平文の .env があります"* ]]' _ "$out"
rm -f "$HOME/.env"

echo "== op-item-add.sh"
reset_stub; bash "$S/op-item-add.sh" AndPad >/dev/null 2>&1; rc=$?
check "大文字の項目名は拒否" bash -c '[ "$1" = 2 ] && [ ! -s "$2" ]' _ "$rc" "$OP_STUB_LOG"
bash "$S/op-item-add.sh" 'アンドパッド' >/dev/null 2>&1; rc=$?
check "日本語の項目名は拒否" [ "$rc" = 2 ]
bash "$S/op-item-add.sh" andpad --password x >/dev/null 2>&1; rc=$?
check "--password（引数でのパスワード）は拒否" [ "$rc" = 2 ]
reset_stub
out="$(printf '%s\n' "$FAKE_SECRET" | bash "$S/op-item-add.sh" andpad --url https://andpad.jp --username "$FAKE_USER" 2>&1)"; rc=$?
check "作成は 0" [ "$rc" = 0 ]
check "参照行を表示（EMAIL）" contains "$out" "ANDPAD_EMAIL=op://Claude-Automation/andpad/username"
check "参照行を表示（PASSWORD）" contains "$out" "ANDPAD_PASSWORD=op://Claude-Automation/andpad/password"
check "パスワードを画面に出さない" not_contains "$out" "$FAKE_SECRET"
check "op item create の出力を出さない" not_contains "$out" "STUB-CREATE-OUTPUT"
check "パスワードを引数に載せない" not_contains "$(cat "$OP_STUB_LOG")" "$FAKE_SECRET"
check "標準入力（-）で渡す" grep -qE 'item create --vault Claude-Automation --format json -$' "$OP_STUB_LOG"
check "テンプレートに値が届く" node -e '
  const t=require(process.argv[1]); const f=Object.fromEntries(t.fields.map(x=>[x.id,x.value]));
  process.exit(t.title==="andpad" && t.category==="LOGIN" && f.username===process.argv[2] && f.password===process.argv[3]
    && t.urls[0].href==="https://andpad.jp" ? 0 : 1)' "$OP_STUB_DIR/template-1.json" "$FAKE_USER" "$FAKE_SECRET"
check "一時ファイルを残さない" tmp_clean
reset_stub
out="$(printf '\n\n' | bash "$S/op-item-add.sh" kintone-keiri --totp 2>&1)"; rc=$?
check "空のパスワードでも作る（アプリで後から）" bash -c '[ "$1" = 0 ] && [[ "$2" == *"パスワード欄は空"* ]]' _ "$rc" "$out"
check "--totp の参照行" contains "$out" "KINTONE_KEIRI_TOTP=op://Claude-Automation/kintone-keiri/one-time password?attribute=otp"
reset_stub
out="$(printf '' | bash "$S/op-item-add.sh" andpad --generate 2>&1)"
check "--generate はパスワード生成を op に頼む" grep -qF -- '--generate-password=20,letters,digits,symbols' "$OP_STUB_LOG"
reset_stub
out="$(OP_STUB_ITEM_EXISTS=1 bash "$S/op-item-add.sh" andpad </dev/null 2>&1)"; rc=$?
check "既存なら作らずに 0" bash -c '[ "$1" = 0 ] && [[ "$2" == *"既にあります"* ]]' _ "$rc" "$out"
check "既存なら create を呼ばない" bash -c "! grep -q 'item create' '$OP_STUB_LOG'"
reset_stub
out="$(OP_STUB_ITEM_STATE=duplicate bash "$S/op-item-add.sh" andpad </dev/null 2>&1)"; rc=$?
check "同じ名前が複数なら止めて一覧を出す" bash -c '[ "$1" = 2 ] && [[ "$2" == *"複数あります"* && "$2" == *aaaa1111* && "$2" == *bbbb2222* ]]' _ "$rc" "$out"
check "同じ名前が複数なら create を呼ばない" bash -c "! grep -q 'item create' '$OP_STUB_LOG'"

echo "== op-env-migrate.sh"
PROJ="$T/repo"; mkdir -p "$PROJ/andpad-browser" "$PROJ/.git" "$T/git-bin"
printf '#!/bin/sh\n[ "$1" = -C ] && [ "$3" = rev-parse ] && [ "$4" = --show-toplevel ] || exit 1\nprintf "%%s\\n" "$OP_TEST_REPO"\n' > "$T/git-bin/git"
chmod +x "$T/git-bin/git"
export OP_TEST_REPO="$PROJ" PATH="$T/git-bin:$PATH"
printf 'node_modules\n' > "$PROJ/.gitignore"
printf '# AndPad メモ: 旧パスワード=%s\nANDPAD_EMAIL=%s\nANDPAD_PASSWORD="%s"\n\nDRY_RUN=1\nSHEET_ID=abc123\nBYPASS_CACHE=1\nSLACK_WEBHOOK=https://hooks.example.com/%s\nDB_DSN=postgres://u:%s@db.example.com/x\nMIRROR=https://u:%s@mirror.example.com/\n' \
  "$FAKE_SECRET" "$FAKE_USER" "$FAKE_SECRET" "$FAKE_SECRET" "$FAKE_SECRET" "$FAKE_SECRET" > "$PROJ/andpad-browser/.env"
reset_stub
out="$(bash "$S/op-env-migrate.sh" "$PROJ/andpad-browser/.env" --yes 2>&1)"; rc=$?
check "移行は 0" [ "$rc" = 0 ]
H='# 値は書かない。1Password の「住所」（秘密参照）だけを書く。実行は op-run.sh -- <コマンド>'
R='op://Claude-Automation/andpad-browser'
expected="$(printf '%s\n' "$H" "ANDPAD_EMAIL=$R/username" "ANDPAD_PASSWORD=$R/password" '' 'DRY_RUN=1' 'SHEET_ID=abc123' 'BYPASS_CACHE=1' \
  "SLACK_WEBHOOK=$R/SLACK_WEBHOOK" "DB_DSN=$R/DB_DSN" "MIRROR=$R/MIRROR")"
check ".env.op は参照と平文の設定だけ（コメントは写さない・空行は残す）" [ "$(cat "$PROJ/andpad-browser/.env.op")" = "$expected" ]
expected="$(printf '%s\n' "$H" "ANDPAD_EMAIL=$R/username" "ANDPAD_PASSWORD=$R/password" '' 'DRY_RUN=<設定値>' 'SHEET_ID=<設定値>' 'BYPASS_CACHE=<設定値>' \
  "SLACK_WEBHOOK=$R/SLACK_WEBHOOK" "DB_DSN=$R/DB_DSN" "MIRROR=$R/MIRROR")"
check ".env.op.example は設定値を <設定値> に伏せる" [ "$(cat "$PROJ/andpad-browser/.env.op.example")" = "$expected" ]
check ".env.op / 見本に値・コメントが残らない" bash -c "! grep -qF -e '$FAKE_SECRET' -e 'hooks.example.com' -e 'メモ' '$PROJ/andpad-browser/.env.op' '$PROJ/andpad-browser/.env.op.example'"
check "元の .env を消す" [ ! -e "$PROJ/andpad-browser/.env" ]
check ".gitignore に .env と .env.op" bash -c "grep -qx .env '$PROJ/.gitignore' && grep -qx .env.op '$PROJ/.gitignore' && grep -qx node_modules '$PROJ/.gitignore'"
check "値を画面に出さない" not_contains "$out" "$FAKE_SECRET"
check "値を引数に載せない" not_contains "$(cat "$OP_STUB_LOG")" "$FAKE_SECRET"
check "テンプレートに username / password で届く" node -e '
  const t=require(process.argv[1]); const f=Object.fromEntries(t.fields.map(x=>[x.id,x.value]));
  process.exit(t.title==="andpad-browser" && f.username===process.argv[2] && f.password===process.argv[3] && !("dry_run" in f)
    && !("sheet_id" in f) && !("bypass_cache" in f) && /hooks/.test(f.slack_webhook) && /@db/.test(f.db_dsn) && /@mirror/.test(f.mirror) ? 0 : 1)' \
  "$OP_STUB_DIR/template-1.json" "$FAKE_USER" "$FAKE_SECRET"
check "一時ファイルを残さない" tmp_clean
out="$(bash "$S/op-env-migrate.sh" "$PROJ/andpad-browser/.env.op.example" --yes 2>&1)"; rc=$?
check ".env.op が既にあれば上書きしない" [ "$rc" = 2 ]
# 既存の項目へ足す（op item edit）・確認で N なら .env を残す
mkdir -p "$PROJ/kintone"; printf 'KINTONE_API_TOKEN=%s\nKINTONE_LOGIN=me\n' "$FAKE_SECRET" > "$PROJ/kintone/.env"
reset_stub
out="$(printf 'n\n' | OP_STUB_ITEM_EXISTS=1 bash "$S/op-env-migrate.sh" "$PROJ/kintone/.env" 2>&1)"; rc=$?
check "既存の項目は edit で足す（標準入力で渡す）" bash -c "[ '$rc' = 0 ] && grep -qx 'SA=0 ARGS=--account daimaruenterprise.1password.com item edit kintone --vault Claude-Automation --format json' '$OP_STUB_LOG'"
check "既存の中身も引数に載せない" bash -c "! grep -q -e '$FAKE_SECRET' -e keep-me '$OP_STUB_LOG'"
check "既存のフィールドを残して足す" node -e '
  const t=require(process.argv[1]); const ids=t.fields.map(x=>x.id);
  process.exit(ids.includes("notesPlain") && ids.includes("kintone_api_token") && ids.includes("username") ? 0 : 1)' "$OP_STUB_DIR/template-1.json"
check "N なら .env を残す" [ -f "$PROJ/kintone/.env" ]
check "TOKEN は KEY 名のフィールドへ" grep -qx 'KINTONE_API_TOKEN=op://Claude-Automation/kintone/KINTONE_API_TOKEN' "$PROJ/kintone/.env.op"
check "LOGIN は username 欄へ" grep -qx 'KINTONE_LOGIN=op://Claude-Automation/kintone/username' "$PROJ/kintone/.env.op"
# 既存の項目に値が入っている欄は上書きしない（--overwrite でだけ上書き）
mkdir -p "$PROJ/garoon"; printf 'GAROON_USER=new-user\nGAROON_PASSWORD=%s\n' "$FAKE_SECRET" > "$PROJ/garoon/.env"
reset_stub
out="$(OP_STUB_ITEM_EXISTS=1 OP_STUB_EXISTING_USER=old-user bash "$S/op-env-migrate.sh" "$PROJ/garoon/.env" --yes 2>&1)"; rc=$?
check "既存の値があれば止めてキー名だけ出す" bash -c '[ "$1" = 2 ] && [[ "$2" == *GAROON_USER* && "$2" == *--overwrite* && "$2" != *old-user* && "$2" != *new-user* ]]' _ "$rc" "$out"
check "止めたときは edit を呼ばず .env も .env.op もそのまま" bash -c "! grep -q 'item edit' '$OP_STUB_LOG' && [ -f '$PROJ/garoon/.env' ] && [ ! -e '$PROJ/garoon/.env.op' ]"
reset_stub
out="$(OP_STUB_ITEM_EXISTS=1 OP_STUB_EXISTING_USER=old-user bash "$S/op-env-migrate.sh" "$PROJ/garoon/.env" --yes --overwrite 2>&1)"; rc=$?
check "--overwrite なら上書きして進む" bash -c "[ '$rc' = 0 ] && grep -q 'item edit garoon' '$OP_STUB_LOG'"
check "--overwrite: 新しい値が届く" node -e '
  const t=require(process.argv[1]); const f=Object.fromEntries(t.fields.map(x=>[x.id,x.value]));
  process.exit(f.username==="new-user" && f.password===process.argv[2] ? 0 : 1)' "$OP_STUB_DIR/template-1.json" "$FAKE_SECRET"
# 同じ名前の項目が複数あれば止める
mkdir -p "$PROJ/dup"; printf 'DUP_PASSWORD=%s\n' "$FAKE_SECRET" > "$PROJ/dup/.env"
out="$(OP_STUB_ITEM_STATE=duplicate bash "$S/op-env-migrate.sh" "$PROJ/dup/.env" --yes 2>&1)"; rc=$?
check "移行: 同じ名前が複数なら止める" bash -c '[ "$1" = 2 ] && [[ "$2" == *"複数あります"* ]] && [ -f "$3" ]' _ "$rc" "$out" "$PROJ/dup/.env"
check "一時ファイルを残さない（移行の後）" tmp_clean

echo ""
echo "結果: ok=$PASS_N fail=$FAIL_N"
[ "$FAIL_N" = 0 ]
