#!/usr/bin/env bash
# =============================================================================
# 無人実行用のトークン（1Password のサービスアカウント）をこの PC に入れる — macOS / Linux 用
# 使い方: 管理者が対象の PC のターミナルに次の1行を貼って Enter
#   curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/op/sa-token.sh | bash
# curl | bash では標準入力がスクリプト本体なので、トークンは端末（/dev/tty）から表示せずに読む。
# 保存は skills/op-secrets/scripts/op-sa-token.sh と同じ処理（Mac=キーチェーン / Linux=secret-tool か 0600 のファイル）。
# =============================================================================
set -uo pipefail

# 途中までしか届かないまま動くのを防ぐため、全体を関数にして最後に呼ぶ
daimaru_op_sa_token(){
  local repo="${DAIMARU_SETUP_REPO:-https://github.com/daimaru-d/daimaru-setup}"
  local dir="${DAIMARU_SETUP_DIR:-$HOME/.daimaru-setup}"
  local sa="$dir/skills/op-secrets/scripts/op-sa-token.sh"

  if [ ! -f "$sa" ]; then
    if ! command -v git >/dev/null 2>&1; then echo "! git がありません。先に daimaru-setup の本体の1行を実行してください" >&2; return 2; fi
    if [ -d "$dir/.git" ]; then git -C "$dir" pull --ff-only </dev/null >/dev/null 2>&1
    else git clone --depth 1 "$repo" "$dir" </dev/null >/dev/null 2>&1; fi
  fi
  if [ ! -f "$sa" ]; then echo "! 道具（daimaru-setup）を取り込めませんでした。ネットワークを確認してください" >&2; return 2; fi

  if ! { : < /dev/tty; } 2>/dev/null; then
    echo "! 端末がないため入力できません。ターミナルを開いて、この1行を貼り付けて実行してください" >&2
    return 2
  fi

  # shellcheck source=/dev/null
  . "$sa"
  OPS_SA_TOKEN_IN=""
  IFS= read -r -s -p "トークンを貼り付けて Enter（表示されません）: " OPS_SA_TOKEN_IN < /dev/tty || true
  printf '\n' >&2
  OPS_SA_TOKEN_IN="${OPS_SA_TOKEN_IN%$'\r'}"
  if [ -z "$OPS_SA_TOKEN_IN" ]; then echo "! 空のため保存しませんでした" >&2; return 2; fi
  if ! ops_sa_store; then OPS_SA_TOKEN_IN=""; echo "! 保存に失敗しました（保管先: $(ops_sa_backend)）" >&2; return 2; fi
  OPS_SA_TOKEN_IN=""
  if ops_sa_exists; then
    echo "サービスアカウントのトークン: あり（保管先: $(ops_sa_backend)）"
    echo "  無人実行に切り替えるには、~/.config/daimaru-op/config の OP_SA_MODE を 1 にします（Claude に「この PC を無人実行に切り替えて」と頼めます）"
  else
    echo "サービスアカウントのトークン: なし（保管先: $(ops_sa_backend)）" >&2
    return 2
  fi
}

daimaru_op_sa_token "$@"
