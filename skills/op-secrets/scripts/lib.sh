# shellcheck shell=bash
# =============================================================================
# op-secrets 共通部品（各スクリプトが source して使う。単独では実行しない）
# - 色つきの表示（setup.sh と同じ見た目）
# - OS 判定（mac / win(Git Bash) / linux）
# - 設定の読み込み: 環境変数 → ~/.config/daimaru-op/config（KEY=VALUE）→ 既定値
# - op（1Password CLI）の所在と --account の付け方
# 約束: 秘密の値は表示しない・引数に載せない・ログに書かない。set -x は使わない。
# 互換: macOS 標準の bash 3.2 と Git Bash で動く書き方（連想配列・mapfile・${v,,} は使わない）
# =============================================================================
[ -n "${OPS_LIB_LOADED:-}" ] && return 0
OPS_LIB_LOADED=1

OPS_GREEN=$'\033[0;32m'; OPS_CYAN=$'\033[0;36m'; OPS_YELLOW=$'\033[0;33m'; OPS_RED=$'\033[0;31m'; OPS_NC=$'\033[0m'
say(){ printf "%s\n" "${OPS_CYAN}$*${OPS_NC}"; }
ok(){ printf "  %s\n" "${OPS_GREEN}✓ $*${OPS_NC}"; }
warn(){ printf "  %s\n" "${OPS_YELLOW}! $*${OPS_NC}"; }
err(){ printf "  %s\n" "${OPS_RED}✗ $*${OPS_NC}"; }
hint(){ printf "      %s\n" "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

case "$(uname -s)" in
  Darwin) OPS_OS=mac;;
  MINGW*|MSYS*|CYGWIN*) OPS_OS=win;;
  Linux) OPS_OS=linux;;
  *) OPS_OS=other;;
esac

OPS_CONFIG_DIR="$HOME/.config/daimaru-op"
OPS_CONFIG_FILE="$OPS_CONFIG_DIR/config"

# 設定ファイルから 1 つ読む（source / eval はしない＝ファイルの中身を実行しない）
ops_config_get(){
  local key="$1" line
  [ -f "$OPS_CONFIG_FILE" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      "$key="*) printf '%s' "${line#*=}"; return 0;;
    esac
  done < "$OPS_CONFIG_FILE"
  return 1
}

ops_load_config(){
  local k v
  for k in OP_ACCOUNT OP_VAULT OP_ENV_FILE OP_SA_MODE; do
    if [ -z "${!k:-}" ]; then
      v="$(ops_config_get "$k" || true)"
      [ -n "$v" ] && printf -v "$k" '%s' "$v"
    fi
  done
  OP_ACCOUNT="${OP_ACCOUNT:-daimaruenterprise.1password.com}"
  OP_VAULT="${OP_VAULT:-Claude-Automation}"
  OP_ENV_FILE="${OP_ENV_FILE:-.env.op}"
  OP_SA_MODE="${OP_SA_MODE:-0}"
}

# op（1Password CLI）を探して OP_BIN に入れる。PATH を優先し、Windows は winget の置き場所も見る
ops_find_op(){
  local c p
  OP_BIN="$(command -v op 2>/dev/null || true)"
  [ -n "$OP_BIN" ] && return 0
  if [ "$OPS_OS" = win ]; then
    p="${LOCALAPPDATA:-}"
    if [ -n "$p" ] && have cygpath; then p="$(cygpath -u "$p")"; fi
    for c in "$p/Microsoft/WinGet/Links/op.exe" "$p"/Microsoft/WinGet/Packages/AgileBits.1Password.CLI*/op.exe \
             "/c/Program Files/1Password CLI/op.exe"; do
      if [ -f "$c" ]; then OP_BIN="$c"; return 0; fi
    done
  fi
  return 1
}

# --account の付け方。サービスアカウントモード（OP_SERVICE_ACCOUNT_TOKEN あり）では付けない（付けると失敗する）
ops_acct_args(){
  OPS_ACCT=()
  if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then OPS_ACCT=(--account "$OP_ACCOUNT"); fi
}

# op をアカウント指定つきで呼ぶ（set -u で空配列でも落ちない書き方）
ops_op(){
  ops_acct_args
  "$OP_BIN" ${OPS_ACCT[@]+"${OPS_ACCT[@]}"} "$@"
}

# キー名が「秘密らしい」か（大文字小文字は区別しない。op-template.js の isSecretKey と同じ規則）
# 長い語（PASSWORD・SECRET・TOKEN など）は含んでいれば秘密。短い語（PASS・KEY）は _ で区切られた語のときだけ
# （BYPASS_CACHE や MONKEY_PATH は秘密ではない）
ops_is_secret_key(){
  local up
  up="$(printf '%s' "$1" | LC_ALL=C tr '[:lower:]' '[:upper:]')"
  case "$up" in
    *PASSWORD*|*PASSWD*|*SECRET*|*TOKEN*|*CREDENTIAL*|*PRIVATE*|*APIKEY*|*ACCESSKEY*) return 0;;
  esac
  case "_${up}_" in
    *_PASS_*|*_KEY_*) return 0;;
  esac
  return 1
}

# 端末（/dev/tty）が開けるか。Claude Code の Bash から呼ばれたときは開けない
ops_have_tty(){
  { : < /dev/tty; } 2>/dev/null
}

# 表示しない入力: 端末が開ければ端末から、無ければ標準入力から読む（Claude Code の Bash では空になる）
# 使い方: ops_read_secret 変数名 "プロンプト"
ops_read_secret(){
  local __v=""
  if ops_have_tty; then IFS= read -r -s -p "$2" __v < /dev/tty || true
  else IFS= read -r -s -p "$2" __v || true; fi
  printf '\n' >&2
  __v="${__v%$'\r'}"
  printf -v "$1" '%s' "$__v"
  __v=""
}

# node（Windows ではネイティブのプログラム）に渡すパス。Git Bash では C:/Users/... の形にする
ops_native_path(){
  if [ "$OPS_OS" = win ] && have cygpath; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# 1Password の項目の有無: exists / missing / duplicate / error を表示する（値は読まない）
ops_item_state(){
  local e rc=0
  e="$(ops_op item get "$1" --vault "$2" --format json 2>&1 >/dev/null)" || rc=$?
  if [ "$rc" = 0 ]; then echo exists; return 0; fi
  case "$(printf '%s' "$e" | LC_ALL=C tr '[:upper:]' '[:lower:]')" in
    *"more than one"*|*multiple*) echo duplicate;;
    *"isn't an item"*|*"not found"*|*"no item"*) echo missing;;
    *) echo error;;
  esac
}

# 同じ名前の項目を一覧する（ID と更新日時だけ。値は読まない）
ops_show_duplicates(){
  ops_op item list --vault "$2" --format json 2>/dev/null | node -e '
    let s = ""; process.stdin.on("data", (d) => { s += d; }).on("end", () => {
      let a = []; try { a = JSON.parse(s || "[]"); } catch (_) { /* 読めなければ空 */ }
      for (const it of a.filter((x) => x.title === process.argv[1])) console.log(`      - ID ${it.id}（更新 ${it.updated_at || "?"}）`);
    });' "$1"
}

# 項目名の検証: 英小文字・数字・ハイフンだけ（先頭は英小文字か数字）。秘密参照は ASCII でないと失敗するため
ops_valid_item_name(){
  case "$1" in
    ''|[!abcdefghijklmnopqrstuvwxyz0123456789]*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1;;
  esac
  return 0
}

# item-name → 環境変数名の頭（andpad-browser → ANDPAD_BROWSER）
ops_var_prefix(){
  printf '%s' "$1" | LC_ALL=C tr 'abcdefghijklmnopqrstuvwxyz-' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_'
}

# .env の 1 行を分解する。結果は OPS_K（キー）と OPS_V（値）に入れる（表示はしない）
# 戻り値: 0=KEY=VALUE / 1=空行かコメント / 2=形が不正
# shellcheck disable=SC2034  # OPS_K / OPS_V は呼び出し側が読む
ops_parse_env_line(){
  local line="${1%$'\r'}" v
  local re='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$'
  OPS_K=""; OPS_V=""
  case "$line" in
    *[![:space:]]*) ;;
    *) return 1;;
  esac
  v="${line#"${line%%[![:space:]]*}"}"
  case "$v" in '#'*) return 1;; esac
  if [[ $line =~ $re ]]; then
    OPS_K="${BASH_REMATCH[2]}"
    v="${BASH_REMATCH[3]}"
    v="${v%"${v##*[![:space:]]}"}"
    case "$v" in
      \"*\") v="${v#\"}"; v="${v%\"}";;
      \'*\') v="${v#\'}"; v="${v%\'}";;
      *) v="${v%%[[:space:]]#*}";;
    esac
    OPS_V="$v"
    v=""
    return 0
  fi
  return 2
}

# OS 別の直し方（1 行）
ops_fix(){ # 引数: mac用 win用 linux用
  case "$OPS_OS" in
    mac) hint "直し方(Mac): $1";;
    win) hint "直し方(Windows): $2";;
    *)   hint "直し方(Linux): $3";;
  esac
}
