#!/usr/bin/env bash
# =============================================================================
# op-run.sh — .env.op に書いた「住所」（秘密参照 op://...）を 1Password から読み、
#             パスワードなどを環境変数として渡してコマンドを動かす安全な入口
#   使い方: op-run.sh [--env-file F] [--sa] -- <コマンド...>
#   例:     op-run.sh -- node create-mitsumori-draft.mjs
# 値は op run が子プロセスの環境変数に入れるだけで、画面に出た値は op run が伏せ字にする。
# 伏せ字を外すオプションは用意しない。
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
ops_load_config

usage(){
  echo "使い方: op-run.sh [--env-file F] [--sa] -- <コマンド...>" >&2
  echo "  例: op-run.sh -- node create-mitsumori-draft.mjs" >&2
  exit 2
}

env_file="$OP_ENV_FILE"
use_sa="$OP_SA_MODE"
while [ $# -gt 0 ]; do
  case "$1" in
    --env-file) [ $# -ge 2 ] || usage; env_file="$2"; shift 2;;
    --env-file=*) env_file="${1#--env-file=}"; shift;;
    --sa) use_sa=1; shift;;
    -h|--help) usage;;
    --) shift; break;;
    *) err "コマンドの前に -- を置いてください（例: op-run.sh -- node x.mjs）"; exit 2;;
  esac
done
[ $# -gt 0 ] || usage

# 1) 注入した値をまるごと表示するコマンドは動かさない
case "$1" in
  printenv) err "printenv は注入した値を表示するため、op-run.sh では動かせません"; exit 2;;
  env|set|export) if [ $# -eq 1 ]; then err "$1 だけを動かすと注入した値がすべて表示されるため、動かせません"; exit 2; fi;;
esac

# 2) env ファイルの検証（値は表示しない。行番号だけ出す）
if [ ! -f "$env_file" ]; then
  err "$env_file がありません"
  hint "既存の .env があるなら: bash ~/.claude/skills/op-secrets/scripts/op-env-migrate.sh <.envの場所>"
  hint "新しく作るなら: .env.op.example を見本に、参照（op://保管庫/項目/フィールド）だけを書きます"
  exit 2
fi
bad_secret=""; bad_form=""; n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  rc=0; ops_parse_env_line "$line" || rc=$?
  case "$rc" in
    0)
      case "$OPS_V" in
        op://*|'') ;;
        *) if ops_is_secret_key "$OPS_K"; then bad_secret="$bad_secret $n"; fi;;
      esac;;
    1) ;;
    *) bad_form="$bad_form $n";;
  esac
done < "$env_file"
OPS_V=""; line=""
if [ -n "$bad_form" ]; then
  err "$env_file の次の行は KEY=値 の形ではありません: 行${bad_form}"
  exit 2
fi
if [ -n "$bad_secret" ]; then
  err "$env_file に、パスワードなどの値がそのまま書かれた行があります: 行${bad_secret}"
  hint ".env.op には参照（op://...）だけを書きます。値は op-item-add.sh で 1Password へ入れてください"
  hint "  bash ~/.claude/skills/op-secrets/scripts/op-item-add.sh <項目名> --url <URL> --username <ID>"
  exit 2
fi

# 3) op の所在とアカウント
if ! ops_find_op; then
  err "1Password CLI（op）が見つかりません"
  ops_fix "brew install 1password-cli" "winget install AgileBits.1Password.CLI" "https://developer.1password.com/docs/cli/get-started/"
  exit 2
fi
if [ "$use_sa" = 1 ] && [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
  # shellcheck source=op-sa-token.sh
  . "$HERE/op-sa-token.sh"
  if ! ops_sa_load; then
    err "サービスアカウントのトークンが保管されていません（op-sa-token.sh set で保管）"
    exit 2
  fi
fi
ops_acct_args

# 4) 実行（op run は既定で出力中の秘密を伏せ字にする）
exec "$OP_BIN" ${OPS_ACCT[@]+"${OPS_ACCT[@]}"} run --env-file "$env_file" --no-masking=false -- "$@"
