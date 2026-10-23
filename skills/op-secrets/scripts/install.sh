#!/usr/bin/env bash
# =============================================================================
# install.sh — op-secrets を Claude Code に入れる（何度実行しても同じ結果）
#   1. このスキル一式を ~/.claude/skills/op-secrets/ へコピー
#   2. ~/.claude/settings.json に見張り（フック）と禁止リスト（deny）を足す
#   3. ~/.config/daimaru-op/config が無ければ既定値で作る
#   4. op-doctor.sh で診断して、次にやることを表示（診断が FAIL でも install は成功扱い）
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

DEST="$HOME/.claude/skills/op-secrets"

say "==> op-secrets を Claude Code に入れます"

# 1) コピー（rsync が無い Windows でも動くよう cp -R。既存は上書き）
mkdir -p "$DEST"
if [ "$(cd "$DEST" && pwd)" = "$SRC" ]; then
  ok "既に $DEST から実行しています（コピーは省略）"
else
  if cp -R "$SRC/." "$DEST/"; then ok "スキルを $DEST に置きました"
  else err "スキルをコピーできませんでした（${DEST}）"; exit 2; fi
fi
chmod 700 "$DEST"/scripts/*.sh 2>/dev/null || true

# 2) Claude Code の設定に見張りと禁止リストを足す
if have node; then
  if node "$DEST/scripts/settings-merge.js"; then ok "Claude Code の設定を更新しました"
  else warn "Claude Code の設定を更新できませんでした（~/.claude/settings.json を確認してください）"; fi
else
  warn "Node.js が無いため、Claude Code の設定を更新できませんでした（daimaru-setup の本体セットアップで入ります）"
fi

# 3) 設定ファイル（無ければ既定値で作る。あれば触らない）
if [ ! -f "$OPS_CONFIG_FILE" ]; then
  mkdir -p "$OPS_CONFIG_DIR"
  {
    echo "# op-secrets の設定（KEY=VALUE）。環境変数があればそちらが優先されます"
    echo "OP_ACCOUNT=daimaruenterprise.1password.com"
    echo "OP_VAULT=Claude-Automation"
    echo "OP_SA_MODE=0"
  } > "$OPS_CONFIG_FILE"
  ok "設定ファイルを作りました: $OPS_CONFIG_FILE"
else
  ok "設定ファイルはそのまま使います: $OPS_CONFIG_FILE"
fi

# 4) 診断（FAIL でも install は成功扱い）
echo ""
bash "$DEST/scripts/op-doctor.sh" || true
echo ""
say "次にやること"
hint "✗ が出た項目は、その下の「直し方」を 1 つずつ実行してください。"
hint "もう一度診断: bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh"
hint "Claude Code を開き直すと、見張りと禁止リストが効きます。"
exit 0
