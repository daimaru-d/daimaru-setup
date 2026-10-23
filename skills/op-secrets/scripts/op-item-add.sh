#!/usr/bin/env bash
# =============================================================================
# op-item-add.sh — 1Password にログイン情報の項目を 1 つ作り、.env.op に貼る行を表示する
#   使い方: op-item-add.sh <項目名> [--url URL] [--username ID] [--generate] [--totp] [--vault V] [--field NAME ...]
#   例:     op-item-add.sh andpad --url https://andpad.jp --username someone@example.com
# - 項目名は英小文字・数字・ハイフンだけ（日本語は秘密参照で使えないため）
# - パスワードは引数で受け取らない。表示されない入力欄で受けるか、--generate で自動で作る。
#   空のまま Enter すると、パスワード欄が空の項目を作る（あとで 1Password アプリで入れる）
# - 値は 0600 の一時ファイル（--template）で op に渡す。引数に載せないのはプロセス一覧に見えるため
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
ops_load_config

usage(){
  echo "使い方: op-item-add.sh <項目名> [--url URL] [--username ID] [--generate] [--totp] [--vault V] [--field NAME ...]" >&2
  exit 2
}

name=""; url=""; user=""; gen=0; totp=0; vault="$OP_VAULT"
fields=()
while [ $# -gt 0 ]; do
  case "$1" in
    --url) [ $# -ge 2 ] || usage; url="$2"; shift 2;;
    --username) [ $# -ge 2 ] || usage; user="$2"; shift 2;;
    --vault) [ $# -ge 2 ] || usage; vault="$2"; shift 2;;
    --field) [ $# -ge 2 ] || usage; fields+=("$2"); shift 2;;
    --generate) gen=1; shift;;
    --totp) totp=1; shift;;
    --password|--password=*) err "パスワードは引数で渡せません（画面に残るため）。このまま実行すると表示されない入力欄で聞きます"; exit 2;;
    -h|--help) usage;;
    -*) err "知らないオプション: $1"; usage;;
    *) if [ -z "$name" ]; then name="$1"; shift; else err "項目名は 1 つだけです"; usage; fi;;
  esac
done
[ -n "$name" ] || usage

if ! ops_valid_item_name "$name"; then
  err "項目名「${name}」は使えません。英小文字・数字・ハイフンだけにしてください（例: andpad、kintone-keiri）"
  hint "日本語や大文字は、1Password の住所（秘密参照）で読めなくなるためです"
  exit 2
fi
for f in ${fields[@]+"${fields[@]}"}; do
  case "$f" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
      err "フィールド名「${f}」は使えません。英数字・_・- だけにしてください"; exit 2;;
  esac
done

if ! ops_find_op; then
  err "1Password CLI（op）が見つかりません"
  ops_fix "brew install 1password-cli" "winget install AgileBits.1Password.CLI" "https://developer.1password.com/docs/cli/get-started/"
  exit 2
fi

# 既にあれば作らない（パスワードの変更は 1Password アプリで）
if ops_op item get "$name" --vault "$vault" --format json >/dev/null 2>&1; then
  ok "項目「${name}」は保管庫「${vault}」に既にあります。パスワードを変えるなら 1Password アプリで変えてください"
  exit 0
fi

pw=""
if [ "$gen" = 0 ]; then
  IFS= read -r -s -p "パスワード（表示されません。空のまま Enter で、あとから 1Password アプリで入れる）: " pw || true
  printf '\n' >&2
  pw="${pw%$'\r'}"
fi
otp=""
if [ "$totp" = 1 ]; then
  IFS= read -r -s -p "2段階認証の設定キー（otpauth://... か英数字。表示されません。空ならアプリで後から）: " otp || true
  printf '\n' >&2
  otp="${otp%$'\r'}"
fi

pw_empty=0
if [ "$gen" = 0 ] && [ -z "$pw" ]; then pw_empty=1; fi

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/op-item-add.XXXXXX")"
chmod 700 "$tmpd"
# 一時ファイルは中身を空にしてから消す
cleanup(){
  local f
  if [ -n "${tmpd:-}" ] && [ -d "$tmpd" ]; then
    for f in "$tmpd"/*; do if [ -f "$f" ]; then : > "$f"; fi; done
    rm -rf "$tmpd"
  fi
}
trap cleanup EXIT INT TERM

# 値は標準入力（printf は bash の内蔵コマンドなのでプロセス一覧に出ない）で部品に渡す
{
  printf '%s\0' "$name" "$url" "$user" "$pw" "$gen" "$otp"
  for f in ${fields[@]+"${fields[@]}"}; do
    fv=""
    IFS= read -r -s -p "「${f}」の値（表示されません）: " fv || true
    printf '\n' >&2
    printf '%s\0' "$f" "${fv%$'\r'}"
    fv=""
  done
} | node "$HERE/op-template.js" login --out "$tmpd/item.json"
otp_given=""; [ -n "$otp" ] && otp_given=1
pw=""; otp=""

gen_args=()
[ "$gen" = 1 ] && gen_args=("--generate-password=20,letters,digits,symbols")
# op item create の出力には項目の中身が含まれるので表示しない（エラーだけ出す）
if ! ops_op item create --vault "$vault" --template "$tmpd/item.json" ${gen_args[@]+"${gen_args[@]}"} --format json >/dev/null; then
  err "項目を作れませんでした（保管庫「${vault}」が見えるか、op-doctor.sh で確認してください）"
  exit 2
fi
ok "1Password の保管庫「${vault}」に項目「${name}」を作りました"
if [ "$pw_empty" = 1 ]; then warn "パスワード欄は空です。1Password アプリで項目「${name}」を開いて入れてください"; fi
if [ "$totp" = 1 ] && [ -z "$otp_given" ]; then warn "2段階認証の設定キーは未登録です。1Password アプリで項目「${name}」に「ワンタイムパスワード」を足してください"; fi

prefix="$(ops_var_prefix "$name")"
case "$user" in *@*) ukey="${prefix}_EMAIL";; *) ukey="${prefix}_USERNAME";; esac
echo ""
say "次の行を .env.op に貼ってください（値ではなく住所なので、貼っても安全です）"
echo "${ukey}=op://${vault}/${name}/username"
echo "${prefix}_PASSWORD=op://${vault}/${name}/password"
[ "$totp" = 1 ] && echo "${prefix}_TOTP=op://${vault}/${name}/one-time password?attribute=otp"
for f in ${fields[@]+"${fields[@]}"}; do
  echo "${prefix}_$(printf '%s' "$f" | LC_ALL=C tr 'abcdefghijklmnopqrstuvwxyz-' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_')=op://${vault}/${name}/${f}"
done
exit 0
