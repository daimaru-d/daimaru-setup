#!/usr/bin/env bash
# =============================================================================
# op-env-migrate.sh — 平文の .env を 1Password へ移し、参照だけの .env.op に置き換える
#   使い方: op-env-migrate.sh <path/to/.env> [--item NAME] [--vault V] [--yes]
#   例:     op-env-migrate.sh andpad-browser/.env
# 流れ: .env を読む（画面には出さない）→ パスワード・ID などを 1Password の 1 項目にまとめる
#       → .env.op（参照だけ）を書く → .gitignore を整える → 元の .env を確認してから消す
# 値は 0600 の一時ファイル（--template）で op に渡す。引数・画面・ログには出さない
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
ops_load_config

usage(){
  echo "使い方: op-env-migrate.sh <path/to/.env> [--item NAME] [--vault V] [--yes]" >&2
  exit 2
}

src=""; item=""; vault="$OP_VAULT"; yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --item) [ $# -ge 2 ] || usage; item="$2"; shift 2;;
    --vault) [ $# -ge 2 ] || usage; vault="$2"; shift 2;;
    --yes|-y) yes=1; shift;;
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

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/op-env-migrate.XXXXXX")"
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

# 既にある項目なら、その中身に足す（取り出した中身は一時ファイルにだけ置く）
mode=create
existing_args=()
if ops_op item get "$item" --vault "$vault" --format json >/dev/null 2>&1; then
  # 足すには今の値ごと読む必要がある（--reveal）。読めなければ壊さないよう止める
  if ops_op item get "$item" --vault "$vault" --reveal --format json > "$tmpd/existing.json" 2>/dev/null; then
    mode=edit
    existing_args=(--existing "$tmpd/existing.json")
  else
    err "項目「${item}」は既にありますが、中身を読み込めませんでした。--item で別の名前を指定してください"
    exit 2
  fi
fi

say "==> $envfile を 1Password の保管庫「${vault}」の項目「${item}」へ移します"
summary="$(node "$HERE/op-template.js" env --env "$envfile" --vault "$vault" --item "$item" \
  --out-template "$tmpd/item.json" --out-envop "$tmpd/env.op" ${existing_args[@]+"${existing_args[@]}"})" || {
  err "移せませんでした（上の理由を確認してください）"; exit 2; }
if [ -f "$tmpd/existing.json" ]; then : > "$tmpd/existing.json"; fi

# 1Password へ（出力には中身が含まれるので表示しない）
if [ "$mode" = edit ]; then
  ops_op item edit "$item" --vault "$vault" --template "$tmpd/item.json" --format json >/dev/null \
    || { err "既存の項目「${item}」を更新できませんでした"; exit 2; }
  ok "既存の項目「${item}」に値を足しました"
else
  ops_op item create --vault "$vault" --template "$tmpd/item.json" --format json >/dev/null \
    || { err "項目「${item}」を作れませんでした（保管庫「${vault}」が見えるか op-doctor.sh で確認）"; exit 2; }
  ok "項目「${item}」を作りました"
fi
: > "$tmpd/item.json"

# キー名と行き先だけ表示（値は出さない）
printf '%s\n' "$summary" | while IFS="$(printf '\t')" read -r kind key field; do
  case "$kind" in
    secret) ok "$key → 1Password（$item / ${field}）";;
    plain)  ok "$key → .env.op にそのまま（秘密ではない設定）";;
  esac
done

cp "$tmpd/env.op" "$envop"
ok "$envop を書きました（参照だけ）"
if [ ! -e "$example" ]; then cp "$tmpd/env.op" "$example"; ok "$example を作りました（見本）"; fi

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
