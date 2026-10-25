#!/usr/bin/env bash
# shellcheck shell=bash
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/google-cloud-sdk/bin:$PATH"
D_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$D_SOURCE" ]; then
  D_HERE="$(cd "$(dirname "$D_SOURCE")/.." 2>/dev/null && pwd || pwd)"
else
  D_HERE="$PWD"
fi
D_ROOT="${DAIMARU_SETUP_ROOT:-$D_HERE}"
D_BASE="${DAIMARU_SETUP_BASE:-https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main}"
case "$D_BASE" in https://*) ;; file://*) [ "${DAIMARU_SETUP_ALLOW_FILE:-0}" = 1 ] || { echo 'DAIMARU_DOCTOR: FAIL missing=base'; exit 2; };; *) echo 'DAIMARU_DOCTOR: FAIL missing=base'; exit 2;; esac
if [ ! -f "$D_ROOT/lib/common.sh" ]; then
  D_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/daimaru-doctor.XXXXXX")" || exit 2
  trap 'rm -rf "$D_ROOT"' EXIT
  mkdir -p "$D_ROOT/lib" "$D_ROOT/profiles"
  curl -fsSL "$D_BASE/lib/common.sh" -o "$D_ROOT/lib/common.sh" || { echo 'DAIMARU_DOCTOR: FAIL missing=common'; exit 2; }
fi
# shellcheck source=lib/common.sh
. "$D_ROOT/lib/common.sh"
if [ -z "${DAIMARU_ROLE:-}" ] && [ -f "$K_STATE" ] && have node; then
  DAIMARU_ROLE="$(state_role)"
fi
DAIMARU_ROLE="${DAIMARU_ROLE:-base}"
if ! valid_role "$DAIMARU_ROLE"; then echo 'DAIMARU_DOCTOR: FAIL missing=role'; exit 2; fi
K_ROLE="$DAIMARU_ROLE"
if [ ! -f "$D_ROOT/profiles/$K_ROLE.env" ]; then
  curl -fsSL "$D_BASE/profiles/$K_ROLE.env" -o "$D_ROOT/profiles/$K_ROLE.env" || { echo 'DAIMARU_DOCTOR: FAIL missing=profile'; exit 2; }
fi
profile_load "$D_ROOT/profiles/$K_ROLE.env" || { echo 'DAIMARU_DOCTOR: FAIL missing=profile'; exit 2; }
D_MISSING=()
fail_item(){ err "$2"; D_MISSING+=("$1"); hint "$3"; }
pass_item(){ ok "$1"; }
skip_item(){ warn "$1: 省略"; }
network_skip(){ [ "${DAIMARU_DOCTOR_SKIP_NETWORK:-0}" = 1 ]; }
case "$(uname -s)" in Darwin) D_OS=mac;; Linux) D_OS=linux;; *) D_OS=other;; esac
say "==> daimaru-setup 診断（${ROLE_LABEL} / ${D_OS}）"
pass_item "OS: $D_OS"
if [ "$D_OS" = mac ]; then
  D_MEM="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
  D_MEM=$((D_MEM / 1024 / 1024 / 1024))
  if have pmset && pmset -g batt 2>/dev/null | grep -q 'Battery Power'; then warn '電源: バッテリー使用中'; hint 'Mac: 電源アダプターを接続してください'; fi
else
  D_MEM="$(awk '/MemTotal:/ {print int($2/1024/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
  if [ -d /sys/class/power_supply ]; then
    for D_SUPPLY in /sys/class/power_supply/*/status; do
      [ -f "$D_SUPPLY" ] || continue
      if grep -q Discharging "$D_SUPPLY" 2>/dev/null; then warn '電源: バッテリー使用中'; hint 'Linux: 電源アダプターを接続してください'; break; fi
    done
  fi
fi
case "$D_MEM" in ''|0) warn 'メモリ: 判定できません'; hint '空き容量を確認してください';;
  *) if [ "$D_MEM" -lt 8 ]; then warn "メモリ: ${D_MEM}GB"; hint '同時に開くアプリを減らしてください'; else pass_item "メモリ: ${D_MEM}GB"; fi;; esac
for D_TOOL in claude node git gh gws code op; do
  D_NEEDED=0
  case "$D_TOOL" in
    claude|node|git|gh) D_NEEDED=1;;
    code) needs vscode && D_NEEDED=1;;
    *) needs "$D_TOOL" && D_NEEDED=1;;
  esac
  if [ "$D_NEEDED" = 0 ]; then continue; fi
  if [ "$D_TOOL" = code ] && [ -x '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' ]; then pass_item 'PATH: code'; continue; fi
  if have "$D_TOOL"; then pass_item "PATH: $D_TOOL"
  else
    case "$D_TOOL" in code) fail_item vscode 'VS Code が見つかりません' 'Mac: brew install --cask visual-studio-code / Linux: 公式パッケージを導入';;
      *) fail_item "$D_TOOL" "$D_TOOL が見つかりません" "Mac: brew install $D_TOOL / Linux: パッケージ管理ツールで $D_TOOL を導入";; esac
  fi
done
if have claude; then
  if claude auth status >/dev/null 2>&1; then pass_item 'Claude: ログイン済み'
  else warn 'Claude: ログイン状態を確認できません'; hint 'claude を起動してログインしてください'; fi
fi
if [ ! -d "$HOME/daimaru-skills/.git" ]; then fail_item hub 'daimaru-skills が見つかりません' 'セットアップをもう一度実行'; fi
if network_skip; then skip_item 'GitHub 権限'; skip_item 'daimaru-skills 更新';
else
  if have gh && gh auth status >/dev/null 2>&1 && gh api repos/daimaru-d/daimaru-skills >/dev/null 2>&1; then pass_item 'GitHub: daimaru-d read'
  else fail_item gh-access 'GitHub: daimaru-d の read 権限を確認できません' 'gh auth login または管理者に daimaru-d read 権限を依頼'; fi
  if [ -d "$HOME/daimaru-skills/.git" ] && have git; then
    if (cd "$HOME/daimaru-skills" && git fetch -q origin && [ "$(git rev-list --count 'HEAD..@{u}' 2>/dev/null)" = 0 ]); then pass_item 'daimaru-skills: 最新'
    else warn 'daimaru-skills: 更新が必要か確認できません'; hint 'セットアップをもう一度実行'; fi
  fi
fi
if needs gws; then
  if ! scopes_cover "$(state_scopes)" "$GWS_SCOPES"; then
    fail_item gws-scopes 'gws: この役割の認可スコープが記録されていません' "DAIMARU_ROLE=$K_ROLE を指定して setup.sh を再実行"
  fi
  if network_skip; then skip_item 'gws 実 API'
  elif have gws; then
    D_GWS_ERR="$(mktemp "${TMPDIR:-/tmp}/daimaru-gws.XXXXXX")"
    if gws drive files list --params '{"pageSize":1,"fields":"files(id)"}' >/dev/null 2>"$D_GWS_ERR"; then pass_item 'gws: Drive 実 API 成功'
    else
      fail_item gws-api 'gws: Drive 実 API に失敗' 'gws auth login -s drive,sheets,gmail を実行'
      if grep -q '401' "$D_GWS_ERR"; then hint "401: ${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$HOME/.config/gws}/token_cache.json を退避して再ログイン"; fi
    fi
    rm -f "$D_GWS_ERR"
  else fail_item gws-api 'gws: 実 API を確認できません' 'npm i -g @googleworkspace/cli'; fi
fi
if needs op; then
  D_OP_DOC="$HOME/.claude/skills/op-secrets/scripts/op-doctor.sh"
  if network_skip; then skip_item '1Password 診断'
  elif [ -f "$D_OP_DOC" ]; then
    D_OP_OUT="$(bash "$D_OP_DOC" 2>&1)"
    if [ "$(printf '%s\n' "$D_OP_OUT" | tail -1)" = 'OP_DOCTOR: PASS' ]; then pass_item '1Password: OP_DOCTOR PASS'
    else fail_item op-doctor '1Password: OP_DOCTOR が PASS ではありません' 'bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh'; fi
  else fail_item op-doctor '1Password の診断スクリプトがありません' 'scripts/op/setup.sh を実行'; fi
fi
if needs vscode; then
  if have code || [ -x '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' ]; then pass_item 'VS Code: 利用可能'; fi
fi
if needs chrome; then
  if [ "$D_OS" = mac ]; then D_CHROME_ROOT="$HOME/Library/Application Support/Google/Chrome"; D_CHROME_APP='/Applications/Google Chrome.app'
  else D_CHROME_ROOT="$HOME/.config/google-chrome"; D_CHROME_APP=''; fi
  if [ -d "$D_CHROME_APP" ] || have google-chrome || have google-chrome-stable; then pass_item 'Chrome: 導入済み'
  else fail_item chrome 'Chrome が見つかりません' 'Mac: brew install --cask google-chrome / Linux: 公式パッケージを導入'; fi
  if [ "$NEEDS_CLAUDE_CHROME" = 1 ]; then
    if chrome_extension_state "$D_CHROME_ROOT"; then pass_item 'Claude in Chrome: 検出'
    else warn 'Claude in Chrome: 未確認'; hint 'Chrome ストアで Claude を検索し、拡張を確認してください'; fi
  fi
fi
for D_TOOL in clasp gcloud; do
  if needs "$D_TOOL"; then
    if have "$D_TOOL"; then pass_item "$D_TOOL: 利用可能"
    else fail_item "$D_TOOL" "$D_TOOL がありません" "Mac: brew / npm で $D_TOOL を導入。Windows: winget / npm で導入"; fi
  fi
done
if needs clasp; then
  if [ -f "$HOME/.clasprc.json" ]; then pass_item 'clasp: ログイン済み'
  else fail_item clasp-login 'clasp にログインしていません' 'clasp login を実行してください'; fi
fi
if needs gcloud; then
  if network_skip; then skip_item 'ADC'
  elif have gcloud && gcloud auth application-default print-access-token >/dev/null 2>&1; then pass_item 'ADC: 利用可能'
  else fail_item adc 'ADC を確認できません' 'gcloud auth application-default login を実行してください'; fi
  if have cloud-sql-proxy; then pass_item 'cloud-sql-proxy: 利用可能'
  else fail_item cloud-sql-proxy 'cloud-sql-proxy がありません' 'cloud-sql-proxy を導入してください'; fi
fi
for D_DIR in "$HOME/Downloads" "$HOME/Desktop"; do
  [ -d "$D_DIR" ] || continue
  while IFS= read -r D_FILE; do
    [ -n "$D_FILE" ] || continue
    warn "機密ファイル候補: $D_FILE"
    hint '不要なら安全な場所へ移し、元のファイルを削除してください'
  done < <(find "$D_DIR" -maxdepth 2 -type f \( -name 'client_secret*.json' -o -name '.env' \) -print 2>/dev/null)
done
if [ ${#D_MISSING[@]} -eq 0 ]; then echo 'DAIMARU_DOCTOR: PASS'; exit 0; fi
D_LIST="$(IFS=,; printf '%s' "${D_MISSING[*]}")"
echo "DAIMARU_DOCTOR: FAIL missing=$D_LIST"
exit 2
