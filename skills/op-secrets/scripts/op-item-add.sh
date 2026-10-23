#!/usr/bin/env bash
# =============================================================================
# op-item-add.sh — 1Password にログイン情報の項目を 1 つ作り、.env.op に貼る行を表示する
#   使い方: op-item-add.sh <項目名> [--url URL] [--username ID] [--generate] [--totp] [--vault V] [--field NAME ...]
#   例:     op-item-add.sh andpad --url https://andpad.jp --username someone@example.com
# - 項目名は英小文字・数字・ハイフンだけ（日本語は秘密参照で使えないため）
# - パスワードは引数で受け取らない。表示されない入力欄で受けるか、--generate で自動で作る。
#   空のまま Enter すると、パスワード欄が空の項目を作る（あとで 1Password アプリで入れる）
#   端末があれば端末から読む。Claude Code の Bash から呼ばれたとき（端末なし）は空のまま作る
# - 値はパイプ（op item create の標準入力 -）で op に渡す。引数・一時ファイルには載せない
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

# 既にあれば作らない（パスワードの変更は 1Password アプリで）。同じ名前が複数あれば止める
state="$(ops_item_state "$name" "$vault")"
case "$state" in
  exists)
    ok "項目「${name}」は保管庫「${vault}」に既にあります。パスワードを変えるなら 1Password アプリで変えてください"
    exit 0;;
  duplicate)
    err "保管庫「${vault}」に「${name}」という名前の項目が複数あります。1Password アプリで 1 つにまとめるか名前を変えてください"
    ops_show_duplicates "$name" "$vault"
    exit 2;;
  error)
    err "1Password に問い合わせできませんでした（サインインと保管庫を op-doctor.sh で確認してください）"
    exit 2;;
esac

pw=""
if [ "$gen" = 0 ]; then
  ops_read_secret pw "パスワード（表示されません。空のまま Enter で、あとから 1Password アプリで入れる）: "
fi
otp=""
if [ "$totp" = 1 ]; then
  ops_read_secret otp "2段階認証の設定キー（otpauth://... か英数字。表示されません。空ならアプリで後から）: "
fi

pw_empty=0
if [ "$gen" = 0 ] && [ -z "$pw" ]; then pw_empty=1; fi

# 値は標準入力（printf は bash の内蔵コマンドなのでプロセス一覧に出ない）で部品に渡し、
# できたテンプレートはこのスクリプトの変数にだけ持つ
tmpl="$({
  printf '%s\0' "$name" "$url" "$user" "$pw" "$gen" "$otp"
  for f in ${fields[@]+"${fields[@]}"}; do
    fv=""
    ops_read_secret fv "「${f}」の値（表示されません）: "
    printf '%s\0' "$f" "$fv"
    fv=""
  done
} | node "$HERE/op-template.js" login)"
otp_given=""; [ -n "$otp" ] && otp_given=1
pw=""; otp=""

gen_args=()
[ "$gen" = 1 ] && gen_args=("--generate-password=20,letters,digits,symbols")
# op item create の出力には項目の中身が含まれるので表示しない（エラーだけ出す）
if ! printf '%s' "$tmpl" | ops_op item create --vault "$vault" ${gen_args[@]+"${gen_args[@]}"} --format json - >/dev/null; then
  tmpl=""
  err "項目を作れませんでした（保管庫「${vault}」が見えるか、op-doctor.sh で確認してください）"
  exit 2
fi
tmpl=""
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
