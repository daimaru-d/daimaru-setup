#!/usr/bin/env bash
# =============================================================================
# 大丸 業務ハブ（daimaru-skills）かんたん初期セットアップ — macOS / Linux 用
# 使い方: ターミナルに次の1行を貼って Enter するだけ
#   curl -fsSL https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/setup.sh | bash
# やること: Claude Code 導入 → 道具(git/node/gh/gcloud/clasp/cloud-sql-proxy) → 取り込み(npm ci)
#           → ログイン(gh/gcloud/ADC/clasp) → 安全バイパスで Claude 起動
# 思想: 1工程が失敗しても止めない。何が出来て何が要対応かを最後にまとめる（非エンジニア向け）。
# =============================================================================
set -uo pipefail
GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; NC=$'\033[0m'
say(){ printf "%s\n" "${CYAN}$*${NC}"; }
ok(){ printf "  %s\n" "${GREEN}✓ $*${NC}"; }
warn(){ printf "  %s\n" "${YELLOW}! $*${NC}"; }
err(){ printf "  %s\n" "${RED}✗ $*${NC}"; }
have(){ command -v "$1" >/dev/null 2>&1; }
TODO=()

# --- OS / パッケージマネージャ判定 ---
case "$(uname -s)" in
  Darwin) OS=mac;;
  Linux)  OS=linux;;
  *) OS=other;;
esac
PM=""
if have brew; then PM=brew
elif have apt-get; then PM=apt
elif have dnf; then PM=dnf
fi
# winget でソフトを入れた直後のように、~/.local/bin 等を PATH に通す
export PATH="$HOME/.local/bin:$HOME/google-cloud-sdk/bin:$PATH"

say "==> 0/6 環境 (OS=$OS, パッケージ管理=$PM)"
if [ "$OS" = "mac" ] && [ -z "$PM" ]; then
  warn "Homebrew が無いため一部の自動導入ができません。https://brew.sh で入れると以降が楽になります。"
fi

# 汎用インストーラ
pm_install(){ # 引数: brewパッケージ名 aptパッケージ名 [--cask]
  local brewpkg="$1" aptpkg="$2" cask="${3:-}"
  case "$PM" in
    brew) if [ "$cask" = "--cask" ]; then brew install --cask "$brewpkg"; else brew install "$brewpkg"; fi;;
    apt)  sudo apt-get update -y >/dev/null 2>&1; sudo apt-get install -y $aptpkg;;
    dnf)  sudo dnf install -y $aptpkg;;
    *) return 1;;
  esac
}

# --- 1/6 Claude Code 本体 ---
say "==> 1/6 Claude Code を導入"
if have claude; then ok "Claude Code ($(claude --version 2>/dev/null | head -1))"
else
  curl -fsSL https://claude.ai/install.sh | bash || warn "Claude Code 自動導入に失敗"
  export PATH="$HOME/.local/bin:$PATH"
  have claude && ok "Claude Code 導入完了" || { err "Claude Code が見つかりません"; TODO+=("Claude Code を手動導入: curl -fsSL https://claude.ai/install.sh | bash"); }
fi

# --- 2/6 開発ツール ---
say "==> 2/6 開発ツール (git / node / gh / gcloud / clasp / cloud-sql-proxy)"
have git  || pm_install git  git  || TODO+=("git を導入")
have node || pm_install node "nodejs npm" || TODO+=("Node.js を導入")
have gh   || pm_install gh   gh   || TODO+=("gh(GitHub CLI) を導入")
if have gcloud; then ok "gcloud"; else
  if [ "$PM" = brew ]; then brew install --cask google-cloud-sdk || TODO+=("gcloud を導入");
  else curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts >/dev/null 2>&1 || TODO+=("gcloud を導入: curl https://sdk.cloud.google.com | bash"); fi
  export PATH="$HOME/google-cloud-sdk/bin:$PATH"
fi
have clasp || npm install -g @google/clasp >/dev/null 2>&1 || TODO+=("clasp を導入: npm install -g @google/clasp")
if have gcloud; then
  have cloud-sql-proxy || gcloud components install cloud-sql-proxy --quiet >/dev/null 2>&1 || TODO+=("cloud-sql-proxy を導入: gcloud components install cloud-sql-proxy")
fi
for t in git node gh gcloud clasp cloud-sql-proxy; do have "$t" && ok "$t" || warn "$t 未導入(後で要対応)"; done

# --- 3/6 GitHub ログイン ---
say "==> 3/6 GitHub にログイン（ブラウザが開いたら、許可されたアカウントで）"
if have gh; then
  gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web
  gh auth setup-git >/dev/null 2>&1 || true
  gh auth status >/dev/null 2>&1 && ok "GitHub ログイン済み" || TODO+=("gh auth login を実行（daimaru-d への read 権限も要確認）")
fi

# --- 4/6 道具箱を取り込む ---
say "==> 4/6 道具箱（daimaru-skills）を取り込み"
cd "$HOME"
if [ -d "$HOME/daimaru-skills/.git" ]; then
  ( cd "$HOME/daimaru-skills" && git pull && git submodule sync --recursive && git submodule update --init --recursive ) || warn "更新に一部失敗"
  ok "更新しました"
else
  git clone --recurse-submodules https://github.com/daimaru-d/daimaru-skills.git || { err "取り込み失敗（多くは権限不足）"; TODO+=("daimaru-d への read 権限を管理者へ依頼"); }
fi
HUB="$HOME/daimaru-skills"
[ -d "$HUB/.git" ] && ok "daimaru-skills を取り込み済み" || true
# DB接続ライブラリ(pg) を用意
if [ -d "$HUB/repos/eigyo-talk-analyzer" ]; then
  ( cd "$HUB/repos/eigyo-talk-analyzer" && npm ci >/dev/null 2>&1 ) && ok "DB接続ライブラリ(pg) 準備OK" || warn "npm ci に失敗(後で $HUB/repos/eigyo-talk-analyzer で npm ci)"
fi

# --- 5/6 BI用ログイン ---
say "==> 5/6 BI用ログイン（ブラウザが開きます）"
if have gcloud; then
  gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q . || gcloud auth login
  gcloud auth application-default print-access-token >/dev/null 2>&1 || gcloud auth application-default login   # ★ADC(proxyが使う)
  gcloud auth application-default print-access-token >/dev/null 2>&1 && ok "ADC 設定済み" || TODO+=("gcloud auth application-default login（ADC）を実行")
fi
if have clasp; then [ -f "$HOME/.clasprc.json" ] || clasp login || true; fi
warn "新規GAS作成には各自Googleで Apps Script API 有効化が必要: https://script.google.com/home/usersettings"

# --- 6/6 まとめ & 起動 ---
echo ""
if [ ${#TODO[@]} -eq 0 ]; then
  say "==> 6/6 準備OK！ 安全バイパスで Claude Code を起動します"
else
  say "==> 6/6 一部 要対応があります（下記）。先に解消するか、Claude起動後に bi-doctor で確認してください"
  for t in "${TODO[@]}"; do warn "$t"; done
fi
echo ""
ok "起動後の流れ: bash .claude/skills/bi-dashboard/harness/bi-doctor.sh  →  /bi-coach"
if [ -d "$HUB/.git" ] && have claude; then
  cd "$HUB"
  # 安全バイパス: settings.json の allow/deny によりプロンプト最小・破壊操作はブロック
  exec claude --permission-mode acceptEdits
else
  warn "Claude もしくは道具箱が未導入のため自動起動しません。上の要対応を解消後、 cd ~/daimaru-skills && claude で起動してください。"
fi
