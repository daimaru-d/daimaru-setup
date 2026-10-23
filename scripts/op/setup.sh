#!/usr/bin/env bash
# =============================================================================
# パスワード金庫（1Password）を Claude Code で使えるようにする — macOS / Linux 用
# 使い方: ターミナルに次の1行を貼って Enter
#   curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/setup.sh | bash
# やること: 1Password CLI の導入 → daimaru-setup の取り込み → op-secrets スキルを Claude Code に入れる
# 思想: 1工程が失敗しても止めない（本体の setup.sh と同じ）。パスワードやトークンは一切扱わない。
# =============================================================================
set -uo pipefail

# curl | bash で途中までしか届かないまま動くのを防ぐため、全体を関数にして最後に呼ぶ
daimaru_op_setup(){
  local GREEN=$'\033[0;32m' CYAN=$'\033[0;36m' YELLOW=$'\033[0;33m' NC=$'\033[0m'
  say(){ printf "%s\n" "${CYAN}$*${NC}"; }
  ok(){ printf "  %s\n" "${GREEN}✓ $*${NC}"; }
  warn(){ printf "  %s\n" "${YELLOW}! $*${NC}"; }
  have(){ command -v "$1" >/dev/null 2>&1; }
  local repo="${DAIMARU_SETUP_REPO:-https://github.com/daimaru-d/daimaru-setup}"
  local dir="${DAIMARU_SETUP_DIR:-$HOME/.daimaru-setup}"

  say "==> 1Password CLI（op）を導入"
  if have op; then ok "1Password CLI（$(op --version 2>/dev/null | head -1)）"
  elif have brew; then
    brew install 1password-cli </dev/null || warn "1Password CLI の自動導入に失敗（brew install 1password-cli を手で実行）"
  elif have apt-get || have dnf; then
    warn "1Password CLI は公式の手順で入れてください（パッケージの置き場所の登録が必要なため、自動では入れません）"
    warn "  https://developer.1password.com/docs/cli/get-started/  の「Linux」"
  else
    warn "1Password CLI を入れてください: https://developer.1password.com/docs/cli/get-started/"
  fi
  hash -r 2>/dev/null || true

  say "==> 道具（daimaru-setup）を取り込み"
  if ! have git; then warn "git がありません。先に本体の setup.sh を実行してください"; return 0; fi
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only </dev/null >/dev/null 2>&1 && ok "更新しました（${dir}）" || warn "更新に失敗（古いまま続けます）"
  else
    git clone --depth 1 "$repo" "$dir" </dev/null >/dev/null 2>&1 && ok "取り込みました（${dir}）" || { warn "取り込みに失敗しました"; return 0; }
  fi

  say "==> op-secrets を Claude Code に入れる"
  bash "$dir/skills/op-secrets/scripts/install.sh" </dev/null || warn "op-secrets の導入で問題がありました（上の表示を確認）"

  echo ""
  say "==> 1Password アプリ側でやること（最初の1回だけ）"
  echo "  1. 1Password アプリを入れて、daimaruenterprise.1password.com にサインイン"
  echo "  2. アプリの 設定 → 開発者 → 「1Password CLI と連携」を ON"
  echo "  3. 確認: bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh"
  return 0
}

daimaru_op_setup "$@"
