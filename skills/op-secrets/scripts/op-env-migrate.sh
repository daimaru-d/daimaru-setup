#!/usr/bin/env bash
# =============================================================================
# op-env-migrate.sh — 平文の .env を 1Password へ移し、参照だけの .env.op に置き換える
#   使い方: op-env-migrate.sh <path/to/.env> [--item NAME] [--vault V] [--yes] [--overwrite]
#   例:     op-env-migrate.sh andpad-browser/.env
# 流れ: .env を読む（画面には出さない）→ パスワード・ID などを 1Password の 1 項目にまとめる
#       → .env.op（参照だけ）を書く → .gitignore を整える → 元の .env を確認してから消す
# 値はパイプ（op item create - / op item edit の標準入力）で op に渡す。引数・一時ファイル・画面・ログには出さない
# 既存の項目に値が入っている欄は上書きしない（--overwrite を付けたときだけ上書き）
# コメント行は写さない。.env.op.example には秘密でない設定も <設定値> に伏せて書く
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
ops_load_config

usage(){
  echo "使い方: op-env-migrate.sh <path/to/.env> [--item NAME] [--vault V] [--yes] [--overwrite]" >&2
  exit 2
}

src=""; item=""; vault="$OP_VAULT"; yes=0; overwrite=0
while [ $# -gt 0 ]; do
  case "$1" in
    --item) [ $# -ge 2 ] || usage; item="$2"; shift 2;;
    --vault) [ $# -ge 2 ] || usage; vault="$2"; shift 2;;
    --yes|-y) yes=1; shift;;
    --overwrite) overwrite=1; shift;;
    -h|--help) usage;;
    -*) err "知らないオプション: $1"; usage;;
    *) if [ -z "$src" ]; then src="$1"; shift; else usage; fi;;
  esac
done
[ -n "$src" ] || usage
if [ ! -f "$src" ]; then err "$src がありません"; exit 2; fi

dir="$(cd "$(dirname "$src")" && pwd)"
envfile="$dir/$(basename "$src")"
envop="$dir/.env.op"
example="$dir/.env.op.example"

# 項目名: 指定が無ければ .env のあるフォルダ名から作る（英小文字・数字・ハイフンだけに）
if [ -z "$item" ]; then
  item="$(basename "$dir" | LC_ALL=C tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ_ .' 'abcdefghijklmnopqrstuvwxyz---' | LC_ALL=C tr -cd 'abcdefghijklmnopqrstuvwxyz0123456789-')"
  while [ "${item#-}" != "$item" ]; do item="${item#-}"; done
fi
if ! ops_valid_item_name "$item"; then
  err "項目名を決められませんでした。--item で英小文字・数字・ハイフンの名前を指定してください（例: --item andpad）"
  exit 2
fi
if [ -e "$envop" ]; then
  err "$envop が既にあります。中身を確かめて手で統合するか、消してからやり直してください（上書きはしません）"
  exit 2
fi
if ! have node; then err "Node.js が見つかりません（daimaru-setup の本体セットアップで入ります）"; exit 2; fi
if ! ops_find_op; then
  err "1Password CLI（op）が見つかりません"
  ops_fix "brew install 1password-cli" "winget install AgileBits.1Password.CLI" "https://developer.1password.com/docs/cli/get-started/"
  exit 2
fi

# 書き出し先（.env.op・見本・キー名の一覧。どれも値は含まない）
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/op-env-migrate.XXXXXX")"
trap 'rm -rf "$tmpd"' EXIT HUP INT TERM

# 既にある項目なら、その中身に足す（今の値ごと読む必要があるので --reveal。読んだ中身は変数にだけ持つ）
mode=create
existing=""
state="$(ops_item_state "$item" "$vault")"
case "$state" in
  exists)
    mode=edit
    if ! existing="$(ops_op item get "$item" --vault "$vault" --reveal --format json 2>/dev/null)"; then
      existing=""
      err "項目「${item}」は既にありますが、中身を読み込めませんでした。--item で別の名前を指定してください"
      exit 2
    fi;;
  duplicate)
    err "保管庫「${vault}」に「${item}」という名前の項目が複数あります。1Password アプリで 1 つにまとめるか、--item で別の名前を指定してください"
    ops_show_duplicates "$item" "$vault"
    exit 2;;
  error)
    err "1Password に問い合わせできませんでした（サインインと保管庫を op-doctor.sh で確認してください）"
    exit 2;;
esac

say "==> $envfile を 1Password の保管庫「${vault}」の項目「${item}」へ移します"
tpl_args=(env --env "$envfile" --vault "$vault" --item "$item"
  --out-envop "$tmpd/env.op" --out-example "$tmpd/env.op.example" --out-summary "$tmpd/summary")
[ "$mode" = edit ] && tpl_args+=(--existing -)
[ "$overwrite" = 1 ] && tpl_args+=(--overwrite)
rc=0
tmpl="$(printf '%s' "$existing" | node "$HERE/op-template.js" "${tpl_args[@]}" 2>"$tmpd/err")" || rc=$?
existing=""
if [ "$rc" = 5 ]; then
  tmpl=""
  keys="$(awk -F '\t' '$1 == "CONFLICT" { print $2 }' "$tmpd/err")"
  err "項目「${item}」の次の欄には既に値が入っているため、上書きせずに止めました: ${keys}"
  hint "1Password アプリで中身を確かめ、上書きしてよければ --overwrite を付けてやり直してください"
  exit 2
elif [ "$rc" != 0 ]; then
  tmpl=""
  cat "$tmpd/err" >&2
  err "移せませんでした（上の理由を確認してください）"
  exit 2
fi

# 1Password へ（出力には中身が含まれるので表示しない）
if [ "$mode" = edit ]; then
  printf '%s' "$tmpl" | ops_op item edit "$item" --vault "$vault" --format json >/dev/null \
    || { tmpl=""; err "既存の項目「${item}」を更新できませんでした"; exit 2; }
  tmpl=""
  ok "既存の項目「${item}」に値を足しました"
else
  printf '%s' "$tmpl" | ops_op item create --vault "$vault" --format json - >/dev/null \
    || { tmpl=""; err "項目「${item}」を作れませんでした（保管庫「${vault}」が見えるか op-doctor.sh で確認）"; exit 2; }
  tmpl=""
  ok "項目「${item}」を作りました"
fi

# キー名と行き先だけ表示（値は出さない）
while IFS="$(printf '\t')" read -r kind key field; do
  case "$kind" in
    secret) ok "$key → 1Password（$item / ${field}）";;
    plain)  ok "$key → .env.op にそのまま（秘密ではない設定）";;
  esac
done < "$tmpd/summary"

cp "$tmpd/env.op" "$envop"
ok "$envop を書きました（参照だけ）"
if [ ! -e "$example" ]; then cp "$tmpd/env.op.example" "$example"; ok "$example を作りました（見本。設定値は <設定値> に伏せています）"; fi

# .gitignore に .env と .env.op を足す（git の中ならリポジトリの一番上に）
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "$dir")"
gi="$root/.gitignore"
for pat in .env .env.op; do
  if [ ! -f "$gi" ] || ! grep -qxF "$pat" "$gi"; then
    if [ -s "$gi" ] && [ -n "$(tail -c 1 "$gi")" ]; then printf '\n' >> "$gi"; fi
    printf '%s\n' "$pat" >> "$gi"
    ok "$gi に $pat を足しました"
  fi
done

# 元の .env を消す（中身を空にしてから消す）
del=n
if [ "$yes" = 1 ]; then del=y
else
  printf "元の %s を消しますか？（値は 1Password に移りました） [y/N]: " "$envfile" >&2
  IFS= read -r del || del=n
fi
case "$del" in
  y|Y|yes|YES) : > "$envfile" && rm -f "$envfile"; ok "元の .env を消しました";;
  *) warn "元の .env は残しました。確認できたら消してください（平文のパスワードが残っています）";;
esac

echo ""
say "次回からは、元のコマンドの前に op-run.sh を付けて動かします"
hint "bash ~/.claude/skills/op-secrets/scripts/op-run.sh -- <元のコマンド>"
hint "dotenv を使うコードも、.env が無くなっても op run が渡す環境変数でそのまま動きます"
