#!/usr/bin/env bash
# macOS / Linux の一回セットアップ。curl | bash とローカル実行の両方に対応。
set -uo pipefail
K_SOURCE="${BASH_SOURCE[0]:-}"
K_HERE=''
if [ -n "$K_SOURCE" ]; then K_HERE="$(cd "$(dirname "$K_SOURCE")" 2>/dev/null && pwd || pwd)"; fi
K_BASE="${DAIMARU_SETUP_BASE:-https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main}"
case "$K_BASE" in https://*) ;; file://*) [ "${DAIMARU_SETUP_ALLOW_FILE:-0}" = 1 ] || { echo 'DAIMARU_SETUP_BASE は https:// のみ指定できます' >&2; exit 2; };; *) echo 'DAIMARU_SETUP_BASE は https:// のみ指定できます' >&2; exit 2;; esac
K_TMP=''
if [ -f "$K_HERE/lib/common.sh" ] && [ -d "$K_HERE/profiles" ]; then
  K_ROOT="$K_HERE"
elif [ "${DAIMARU_DRY_RUN:-0}" = 1 ]; then
  K_PREVIEW_ROLE="${DAIMARU_ROLE:-base}"
  if [ -z "${DAIMARU_ROLE:-}" ] && [ -f "$HOME/.config/daimaru-setup/state.json" ] && command -v node >/dev/null 2>&1; then
    K_PREVIEW_ROLE="$(node -e 'try{process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).role||"base")}catch(e){process.stdout.write("base")}' "$HOME/.config/daimaru-setup/state.json")"
  fi
  case "$K_PREVIEW_ROLE" in base|sekkei|togo|yochi|somu-keiri) ;; *) echo '役割名が正しくありません' >&2; exit 2;; esac
  echo "予定: $K_PREVIEW_ROLE の準備（オンラインのプロファイル取得を省略）"
  echo '予定: Claude Code / Git / Node.js / GitHub CLI / daimaru-skills / doctor'
  case "$K_PREVIEW_ROLE" in
    sekkei) echo '予定: VS Code / gws / Chrome / 1Password / Chrome 拡張の案内';;
    togo) echo '予定: gws / clasp / gcloud / ADC / 1Password';;
    yochi) echo '予定: gws / 1Password';;
    somu-keiri) echo '予定: gws / 1Password / 経理の追加手順';;
  esac
  exit 0
else
  K_TMP="$(mktemp -d "${TMPDIR:-/tmp}/daimaru-setup.XXXXXX")" || exit 2
  trap 'rm -rf "$K_TMP"' EXIT
  mkdir -p "$K_TMP/lib" "$K_TMP/profiles" "$K_TMP/doctor"
  curl -fsSL "$K_BASE/lib/common.sh" -o "$K_TMP/lib/common.sh" || exit 2
  K_ROOT="$K_TMP"
fi
# shellcheck source=lib/common.sh
. "$K_ROOT/lib/common.sh"
role_select || exit 2
if [ ! -f "$K_ROOT/profiles/$K_ROLE.env" ]; then
  curl -fsSL "$K_BASE/profiles/$K_ROLE.env" -o "$K_ROOT/profiles/$K_ROLE.env" || exit 2
fi
profile_load "$K_ROOT/profiles/$K_ROLE.env" || { err 'プロファイルを読めません'; exit 2; }
export DAIMARU_ROLE="$K_ROLE"
say "==> ${ROLE_LABEL} の準備"
[ -n "$NOTE" ] && hint "$NOTE"
if needs gws && ! dry_run; then check_gws_secret >/dev/null 2>&1 || true; fi
case "$(uname -s)" in Darwin) K_OS=mac;; Linux) K_OS=linux;; *) K_OS=other;; esac
K_HUB="$HOME/daimaru-skills"
if ! dry_run; then cleanup_gws_temps; fi
export PATH="$HOME/.local/bin:$HOME/google-cloud-sdk/bin:$PATH"
if have brew; then K_PM=brew; elif have apt-get; then K_PM=apt; elif have dnf; then K_PM=dnf; else K_PM=none; fi
check_claude(){ have claude; }
install_claude(){ curl -fsSL https://claude.ai/install.sh | bash; }
check_git(){ have git; }; install_git(){ install_pkg git git; }
check_node(){ have node; }; install_node(){ install_pkg node 'nodejs npm'; }
check_gh(){ have gh; }; install_gh(){ install_pkg gh gh; }
check_gh_auth(){ have gh && gh auth status >/dev/null 2>&1 && gh api repos/daimaru-d/daimaru-skills >/dev/null 2>&1; }
login_gh(){
  have gh || return 1
  gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web || return 1
  gh api repos/daimaru-d/daimaru-skills >/dev/null 2>&1 || { hint '管理者に daimaru-d の read 権限を依頼してください'; return 1; }
}
check_hub(){
  [ -d "$K_HUB/.git" ] || return 1
  if [ -f "$K_HUB/.gitmodules" ]; then (cd "$K_HUB" && git submodule update --init --recursive) || return 1; fi
}
clone_hub(){ have git && git clone --recurse-submodules https://github.com/daimaru-d/daimaru-skills.git "$K_HUB"; }
check_never(){ return 1; }
update_hub(){
  if [ -d "$K_HUB/.git" ]; then (cd "$K_HUB" && git pull && git submodule sync --recursive && git submodule update --init --recursive)
  else clone_hub; fi
}
check_npm_ci(){ [ -d "$K_HUB/repos/eigyo-talk-analyzer/node_modules/pg" ] || [ ! -d "$K_HUB/repos/eigyo-talk-analyzer" ]; }
install_npm_ci(){ [ -d "$K_HUB/repos/eigyo-talk-analyzer" ] && (cd "$K_HUB/repos/eigyo-talk-analyzer" && npm ci >/dev/null 2>&1); }
check_op(){ have op && [ -f "$HOME/.claude/skills/op-secrets/scripts/op-doctor.sh" ]; }
install_op(){
  if [ -f "$K_HERE/scripts/op/setup.sh" ]; then bash "$K_HERE/scripts/op/setup.sh"
  else curl -fsSL "$K_BASE/scripts/op/setup.sh" | bash; fi
  check_op
}
check_gws(){ have gws; }
install_gws(){ have npm && npm i -g @googleworkspace/cli >/dev/null 2>&1; }
check_gws_auth(){ have gws && scopes_cover "$(state_scopes)" "$GWS_SCOPES" && gws drive files list --params '{"pageSize":1,"fields":"files(id)"}' >/dev/null 2>&1; }
login_gws(){
  check_gws_secret || { hint '管理者に 1Password の招待を頼んでください'; return 1; }
  gws auth login -s "$GWS_SCOPES" || return 1
  gws drive files list --params '{"pageSize":1,"fields":"files(id)"}' >/dev/null 2>&1 || return 1
  state_set_scopes "$GWS_SCOPES"
}
check_vscode(){ have code || [ -x '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' ]; }
install_vscode(){
  case "$K_OS" in mac) have brew && brew install --cask visual-studio-code;;
    linux) hint 'Linux: VS Code の公式パッケージを導入してください'; return 1;;
    *) return 1;; esac
}
code_cli(){ if have code; then code "$@"; else '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' "$@"; fi; }
check_extensions(){
  local ext
  check_vscode || return 1
  for ext in ms-ceintl.vscode-language-pack-ja anthropic.claude-code $VSCODE_EXTENSIONS; do
    code_cli --list-extensions 2>/dev/null | grep -qiFx "$ext" || return 1
  done
}
install_extensions(){
  local ext
  check_vscode || return 1
  for ext in ms-ceintl.vscode-language-pack-ja anthropic.claude-code $VSCODE_EXTENSIONS; do
    code_cli --list-extensions 2>/dev/null | grep -qiFx "$ext" || code_cli --install-extension "$ext" >/dev/null || return 1
  done
}
check_chrome(){ [ -d '/Applications/Google Chrome.app' ] || have google-chrome || have google-chrome-stable; }
install_chrome(){ case "$K_OS" in mac) have brew && brew install --cask google-chrome;; linux) hint 'Linux: Chrome の公式パッケージを導入してください'; return 1;; *) return 1;; esac; }
check_chrome_extension(){
  case "$K_OS" in mac) chrome_extension_state "$HOME/Library/Application Support/Google/Chrome";;
    *) chrome_extension_state "$HOME/.config/google-chrome";; esac
}
show_chrome_extension(){
  hint 'Chrome のストアで Claude を検索し、追加ボタンを押してください（未確認）'
  if [ "$(state_get chrome-extension-open)" != ok ]; then
    case "$K_OS" in mac) open 'https://chromewebstore.google.com/search/Claude' >/dev/null 2>&1;;
      linux) have xdg-open && xdg-open 'https://chromewebstore.google.com/search/Claude' >/dev/null 2>&1;; esac
    state_set chrome-extension-open ok || true
  fi
  return 1
}
check_skills(){ [ ! -f "$K_HUB/profiles/$K_ROLE.json" ] && return 0; return 1; }
install_skills(){
  copy_skills "$K_HUB" "$K_ROLE" || return 1
}
check_clasp(){ have clasp; }; install_clasp(){ have npm && npm install -g @google/clasp >/dev/null 2>&1; }
check_clasp_auth(){ [ -f "$HOME/.clasprc.json" ]; }; login_clasp(){ have clasp && clasp login; }
check_gcloud(){ have gcloud; }
install_gcloud(){
  if [ "$K_PM" = brew ]; then brew install --cask google-cloud-sdk
  else curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts >/dev/null 2>&1; fi
}
check_gcloud_auth(){ have gcloud && gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; }
login_gcloud(){ have gcloud && gcloud auth login; }
check_adc(){ have gcloud && gcloud auth application-default print-access-token >/dev/null 2>&1; }
login_adc(){ have gcloud && gcloud auth application-default login; }
check_proxy(){ have cloud-sql-proxy; }; install_proxy(){ have gcloud && gcloud components install cloud-sql-proxy --quiet >/dev/null 2>&1; }
run_step claude check_claude install_claude || true
run_step git check_git install_git || true
run_step node check_node install_node || true
run_step gh check_gh install_gh || true
run_step gh-access check_gh_auth login_gh || true
if ! dry_run && have gh; then gh auth setup-git >/dev/null 2>&1 || true; fi
K_HUB_EXISTED=0
[ -d "$K_HUB/.git" ] && K_HUB_EXISTED=1
run_step hub check_hub clone_hub || true
if ! dry_run && ! update_only && [ "$K_HUB_EXISTED" = 1 ]; then
  (cd "$K_HUB" && git pull --ff-only >/dev/null 2>&1 && { [ ! -f .gitmodules ] || git submodule update --init --recursive >/dev/null 2>&1; }) || warn 'daimaru-skills を更新できませんでした。現在の内容で続行します'
fi
if update_only; then run_step hub-update check_never update_hub || true; fi
run_step npm-ci check_npm_ci install_npm_ci || true
if needs op; then run_step op check_op install_op || true; fi
if needs gws; then
  run_step gws check_gws install_gws || true
  run_step gws-secret check_gws_secret install_gws_secret || true
  run_step gws-auth check_gws_auth login_gws || true
fi
if needs vscode; then
  run_step vscode check_vscode install_vscode || true
  run_step vscode-extensions check_extensions install_extensions || true
fi
if needs chrome; then
  run_step chrome check_chrome install_chrome || true
  if [ "$NEEDS_CLAUDE_CHROME" = 1 ]; then run_step chrome-extension check_chrome_extension show_chrome_extension || true; fi
fi
if needs clasp; then run_step clasp check_clasp install_clasp || true; run_step clasp-auth check_clasp_auth login_clasp || true; fi
if needs gcloud; then
  run_step gcloud check_gcloud install_gcloud || true
  run_step gcloud-auth check_gcloud_auth login_gcloud || true
  run_step adc check_adc login_adc || true
  run_step cloud-sql-proxy check_proxy install_proxy || true
fi
run_step skills check_skills install_skills || true
if [ "$K_ROLE" = somu-keiri ]; then hint '総務経理の追加手順: scripts/keiri/onboard.sh を参照してください'; fi
if dry_run; then say '予定の表示を完了しました'; exit 0; fi
if update_only; then say '更新を完了しました'; exit 0; fi
if [ ! -f "$K_ROOT/doctor/doctor.sh" ]; then curl -fsSL "$K_BASE/doctor/doctor.sh" -o "$K_ROOT/doctor/doctor.sh" || true; fi
if [ -f "$K_ROOT/doctor/doctor.sh" ]; then
  DAIMARU_SETUP_ROOT="$K_ROOT" bash "$K_ROOT/doctor/doctor.sh" || true
else warn 'doctor を取得できませんでした'; fi
if [ -d "$K_HUB/.git" ] && have claude; then
  cleanup_gws_temps
  cd "$(role_workspace "$K_HUB" "$K_ROLE")" || exit 0
  if [ -n "$K_TMP" ]; then rm -rf "$K_TMP"; K_TMP=''; fi
  exec claude --permission-mode acceptEdits
fi
warn 'Claude または道具箱が未導入です。doctor の案内を確認してください'
