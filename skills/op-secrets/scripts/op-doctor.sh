#!/usr/bin/env bash
# =============================================================================
# op-doctor.sh — 1Password と Claude Code の連携が使える状態かを診断する
#   使い方: bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh
#   各行 ✓（OK）/ !（注意）/ ✗（要対応）と、OS 別の直し方を 1 行ずつ表示する
#   最終行（機械が読む）: OP_DOCTOR: PASS  または  OP_DOCTOR: FAIL missing=<項目番号,...>
#   終了コード: 0=PASS / 2=FAIL
# パスワードなどの値は読まない・表示しない（.env は「値が入っている行の数」だけ数える）
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
ops_load_config

missing=()
fail(){ missing+=("$1"); }

say "==> op-secrets 診断（アカウント: $OP_ACCOUNT / 保管庫: $OP_VAULT / OS: ${OPS_OS}）"

# 7 を先に準備: 無人実行モードならトークンを読み込む（表示しない）
sa_loaded=0
if [ "$OP_SA_MODE" = 1 ] && [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  # shellcheck source=op-sa-token.sh
  . "$HERE/op-sa-token.sh"
  if ops_sa_load; then sa_loaded=1; fi
elif [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  sa_loaded=1
fi

# 1) op があるか・2.x か
op_ok=0
if ops_find_op; then
  ver="$("$OP_BIN" --version 2>/dev/null | head -1 | tr -d '\r')"
  case "$ver" in
    2.*) ok "1. 1Password CLI（op）$ver"; op_ok=1;;
    *) err "1. 1Password CLI（op）のバージョンが 2.x ではありません（${ver:-不明}）"
       ops_fix "brew upgrade 1password-cli" "winget upgrade AgileBits.1Password.CLI" "https://developer.1password.com/docs/cli/get-started/"
       fail 1;;
  esac
else
  err "1. 1Password CLI（op）が見つかりません"
  ops_fix "brew install 1password-cli" "winget install AgileBits.1Password.CLI（入れた後は Git Bash を開き直す）" "https://developer.1password.com/docs/cli/get-started/ の apt / rpm の手順"
  fail 1
fi

# 2) 1Password アプリとの連携（サインインできているか）
if [ "$op_ok" = 1 ]; then
  if ops_op whoami >/dev/null 2>&1; then
    if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then ok "2. サービスアカウントでサインインできています（無人実行）"
    else ok "2. 1Password アプリと連携してサインインできています"; fi
  else
    err "2. 1Password にサインインできていません"
    hint "直し方: 1Password アプリを入れてサインイン → 設定 → 開発者 → 「1Password CLI と連携」を ON"
    hint "        → op signin --account $OP_ACCOUNT"
    fail 2
  fi
else
  err "2. op が無いので確認できません"; fail 2
fi

# 3) アカウントが登録されているか
if [ "$op_ok" = 1 ]; then
  if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    ok "3. サービスアカウントで動くため、アカウントの登録は不要です"
  elif "$OP_BIN" account list 2>/dev/null | grep -qiF "$OP_ACCOUNT"; then
    ok "3. アカウント $OP_ACCOUNT が登録されています"
  else
    err "3. アカウント $OP_ACCOUNT が op に登録されていません"
    hint "直し方: 1Password アプリで $OP_ACCOUNT にサインイン → op signin --account $OP_ACCOUNT"
    fail 3
  fi
else
  err "3. op が無いので確認できません"; fail 3
fi

# 4) 保管庫が見えるか
if [ "$op_ok" = 1 ]; then
  if ops_op vault get "$OP_VAULT" --format json >/dev/null 2>&1; then
    ok "4. 保管庫「${OP_VAULT}」が見えます"
  else
    err "4. 保管庫「${OP_VAULT}」が見えません"
    hint "直し方: 1Password の管理者に、保管庫「${OP_VAULT}」をあなたに共有するよう依頼してください"
    fail 4
  fi
else
  err "4. op が無いので確認できません"; fail 4
fi

# 5) Claude Code の見張り（フック）と禁止リスト
if have node; then
  if out="$(node "$HERE/settings-merge.js" --check 2>&1)"; then
    ok "5. Claude Code の見張りと禁止リストが入っています"
  else
    err "5. Claude Code の設定に見張り・禁止リストが足りません"
    printf '%s\n' "$out" | while IFS= read -r l; do hint "$l"; done
    hint "直し方: bash ~/.claude/skills/op-secrets/scripts/install.sh をもう一度実行"
    fail 5
  fi
else
  err "5. Node.js が無いので確認できません（daimaru-setup の本体セットアップで入ります）"; fail 5
fi

# 6) 平文の .env が残っていないか（中身は表示しない。値が入っている行の数だけ数える）
#    ホームフォルダ直下で実行したときは省略する（書類やデスクトップまで探すと時間がかかり、
#    Mac ではフォルダへのアクセス許可を何度も聞かれるため）
found=0
scan_list=""
if [ "$(pwd)" = "$(cd "$HOME" && pwd)" ]; then
  found=2
else
  scan_list="$(find . -maxdepth 3 \( -name node_modules -o -name .git \) -prune -o -type f -name '.env*' -print 2>/dev/null \
    | grep -E '/\.env(\.[A-Za-z0-9_-]+)?$' | grep -vE '/\.env\.(op|example|sample)$')"
fi
while IFS= read -r f; do
  [ -n "$f" ] || continue
  cnt="$(awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ || !/=/ { next }
    {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/^["'\'']|["'\'']$/, "", v)
      if (v != "" && v !~ /^op:\/\//) n++
    }
    END { print n + 0 }' "$f" 2>/dev/null)"
  warn "6. 平文の .env があります: ${f}（値が入っている行: ${cnt:-?}）"
  hint "直し方: bash ~/.claude/skills/op-secrets/scripts/op-env-migrate.sh \"$f\""
  found=1
done <<EOF
$scan_list
EOF
[ "$found" = 0 ] && ok "6. このフォルダ（3 階層まで）に平文の .env はありません"
[ "$found" = 2 ] && ok "6. ホームフォルダでは .env の検査を省略しました（作業フォルダで実行すると検査します）"

# 7) 無人実行のトークン
if [ "$OP_SA_MODE" = 1 ]; then
  if [ "$sa_loaded" = 1 ]; then ok "7. 無人実行のトークンが保管されています"
  else
    err "7. 無人実行（OP_SA_MODE=1）なのにトークンが保管されていません"
    hint "直し方: bash ~/.claude/skills/op-secrets/scripts/op-sa-token.sh set（トークンは管理者から受け取る）"
    fail 7
  fi
fi

echo ""
if [ ${#missing[@]} -eq 0 ]; then
  echo "OP_DOCTOR: PASS"
  exit 0
fi
list="$(IFS=,; echo "${missing[*]}")"
echo "OP_DOCTOR: FAIL missing=$list"
exit 2
