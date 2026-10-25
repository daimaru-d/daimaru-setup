#!/usr/bin/env bash
# shellcheck shell=bash
K_GREEN=$'\033[0;32m'; K_CYAN=$'\033[0;36m'; K_YELLOW=$'\033[0;33m'; K_RED=$'\033[0;31m'; K_NC=$'\033[0m'
say(){ printf '%s\n' "${K_CYAN}$*${K_NC}"; }
ok(){ printf '  %s\n' "${K_GREEN}✓ $*${K_NC}"; }
warn(){ printf '  %s\n' "${K_YELLOW}! $*${K_NC}"; }
err(){ printf '  %s\n' "${K_RED}✗ $*${K_NC}"; }
hint(){ printf '      %s\n' "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }
dry_run(){ [ "${DAIMARU_DRY_RUN:-0}" = 1 ]; }
update_only(){ [ "${DAIMARU_UPDATE:-0}" = 1 ]; }
K_STATE="$HOME/.config/daimaru-setup/state.json"
migrate_state(){
  local old="$HOME/.daimaru-setup" target="${K_STATE%/*}"
  dry_run && return 0
  [ -f "$old/state.json" ] && [ ! -e "$K_STATE" ] && [ ! -e "$old/.git" ] || return 0
  [ "$(find "$old" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" = 1 ] || return 0
  mkdir -p "$target" || return 1
  mv "$old/state.json" "$K_STATE" || return 1
  rmdir "$old" || true
}
migrate_state
K_OP_VAULT_DEFAULT=Claude-Automation
K_OP_ITEM=gws-oauth-client
K_OP_FIELD=client_secret.json
k_op_vault(){
  local v="${OP_VAULT:-}" line
  if [ -z "$v" ] && [ -f "$HOME/.config/daimaru-op/config" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      case "$line" in OP_VAULT=*) v="${line#*=}"; break;; esac
    done < "$HOME/.config/daimaru-op/config"
  fi
  v="${v:-$K_OP_VAULT_DEFAULT}"
  case "$v" in *[!a-zA-Z0-9-]*) return 1;; esac
  printf '%s' "$v"
}
k_op_ref(){
  local vault
  vault="$(k_op_vault)" || return 1
  printf 'op://%s/%s/%s' "$vault" "$K_OP_ITEM" "$K_OP_FIELD"
}
k_op_account(){
  local account="${OP_ACCOUNT:-}" line
  if [ -z "$account" ] && [ -f "$HOME/.config/daimaru-op/config" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      case "$line" in OP_ACCOUNT=*) account="${line#*=}"; break;; esac
    done < "$HOME/.config/daimaru-op/config"
  fi
  printf '%s' "${account:-daimaruenterprise.1password.com}"
}
k_op_read(){
  local account
  if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then op read "$1"
  else account="$(k_op_account)"; op --account "$account" read "$1"; fi
}
op_ready(){
  local doctor="$HOME/.claude/skills/op-secrets/scripts/op-doctor.sh" output
  have op && [ -f "$doctor" ] || return 1
  output="$(bash "$doctor" 2>/dev/null)" || return 1
  [ "${output##*$'\n'}" = 'OP_DOCTOR: PASS' ]
}
check_gws_secret(){
  local f="${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$HOME/.config/gws}/client_secret.json"
  [ -f "$f" ] && chmod 600 "$f" && have node && node -e 'try{let x=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.exit(x.installed&&x.installed.client_id&&x.installed.client_secret?0:1)}catch(e){process.exit(1)}' "$f" 2>/dev/null
}
cleanup_gws_temps(){
  local dir="${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$HOME/.config/gws}"
  rm -f "$dir"/.client_secret-* "$dir/.op-error.tmp"
}
install_gws_secret(){
  local dir="${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$HOME/.config/gws}" tmp ref
  have op || { hint '管理者に 1Password の招待を頼んでください'; return 1; }
  ref="$(k_op_ref)" || return 1
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" || return 1
  cleanup_gws_temps
  tmp="$(mktemp "$dir/.client_secret-XXXXXX")" || return 1
  ( trap 'rm -f "$tmp"' EXIT
    chmod 600 "$tmp" || exit 1
    k_op_read "$ref" > "$tmp" 2>/dev/null || { hint '管理者に 1Password の招待を頼んでください'; exit 1; }
    node -e 'try{let x=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.exit(x.installed&&x.installed.client_id&&x.installed.client_secret?0:1)}catch(e){process.exit(1)}' "$tmp" 2>/dev/null || { hint '共有 OAuth 設定を確認できません'; exit 1; }
    mv -f "$tmp" "$dir/client_secret.json"
  )
}
valid_role(){ case "$1" in base|sekkei|togo|yochi|somu-keiri) return 0;; esac; return 1; }
role_select(){
  K_ROLE="${DAIMARU_ROLE:-}"
  if [ -z "$K_ROLE" ]; then
    K_ROLE="$(state_role)"
    if [ -n "$K_ROLE" ] && valid_role "$K_ROLE"; then return 0; fi
    K_ROLE=base
    if ! dry_run && { [ -t 0 ] || { [ -r /dev/tty ] && [ -w /dev/tty ] && (: < /dev/tty) 2>/dev/null; }; }; then
      printf '役割 (base/sekkei/togo/yochi/somu-keiri、Enter=base): ' >&2
      if [ -t 0 ]; then IFS= read -r K_ROLE || K_ROLE=base
      else IFS= read -r K_ROLE < /dev/tty || K_ROLE=base; fi
      K_ROLE="${K_ROLE:-base}"
    elif ! dry_run; then
      hint '対話端末がないため、役割は base で進めます（DAIMARU_ROLE で指定できます）'
    fi
  fi
  if ! valid_role "$K_ROLE"; then err '役割名が正しくありません'; return 2; fi
}
state_role(){
  [ -f "$K_STATE" ] && have node || return 0
  node -e 'try{process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).role||"")}catch(e){}' "$K_STATE" 2>/dev/null
}
# shellcheck disable=SC2034 # 呼び出し側の setup/doctor が参照する値
profile_load(){
  local file="$1" line key value
  ROLE_LABEL=; TOOLS=; GWS_SCOPES=; VSCODE_EXTENSIONS=; NEEDS_CLAUDE_CHROME=0; NOTE=
  [ -f "$file" ] || { err 'プロファイルが見つかりません'; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue;; esac
    case "$line" in *=*) key="${line%%=*}"; value="${line#*=}";; *) return 1;; esac
    case "$key" in
      ROLE_LABEL) ROLE_LABEL="$value";; TOOLS) TOOLS="$value";; GWS_SCOPES) GWS_SCOPES="$value";;
      VSCODE_EXTENSIONS) VSCODE_EXTENSIONS="$value";; NEEDS_CLAUDE_CHROME) NEEDS_CLAUDE_CHROME="$value";; NOTE) NOTE="$value";;
      *) return 1;;
    esac
  done < "$file"
  case "$NEEDS_CLAUDE_CHROME" in 0|1) ;; *) return 1;; esac
  case "$TOOLS $VSCODE_EXTENSIONS" in *[!a-zA-Z0-9_.\ -]*) return 1;; esac
  case "$GWS_SCOPES" in *[!a-z,\ -]*) return 1;; esac
}
needs(){ case " $TOOLS " in *" $1 "*) return 0;; esac; return 1; }
install_pkg(){
  case "$K_PM" in
    brew) brew install "$1";;
    apt)
      # shellcheck disable=SC2086 # 複数のパッケージ名を別引数にする
      sudo apt-get update -y >/dev/null 2>&1 && sudo apt-get install -y $2;;
    dnf)
      # shellcheck disable=SC2086 # 複数のパッケージ名を別引数にする
      sudo dnf install -y $2;;
    *) return 1;;
  esac
}
install_npm_global(){
  local prefix
  have npm || return 1
  if [ "${K_OS:-}" = linux ]; then
    prefix="$(npm config get prefix 2>/dev/null)" || return 1
    if [ -z "$prefix" ] || [ ! -w "$prefix" ]; then
      mkdir -p "$HOME/.local/bin" || return 1
      export PATH="$HOME/.local/bin:$PATH"
      npm install -g --prefix "$HOME/.local" "$1" >/dev/null 2>&1
      return $?
    fi
  fi
  npm install -g "$1" >/dev/null 2>&1
}
state_get(){
  have node || return 1
  node -e 'try {const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));if(s.role===process.argv[2]) process.stdout.write((s.steps||{})[process.argv[3]]||"")}catch(e){}' "$K_STATE" "$K_ROLE" "$1" 2>/dev/null
}
scopes_cover(){
  local have_scopes=",$1," required="$2" scope old_ifs="$IFS"
  IFS=,
  for scope in $required; do case "$have_scopes" in *",$scope,"*) ;; *) IFS="$old_ifs"; return 1;; esac; done
  IFS="$old_ifs"
}
state_scopes(){
  [ -f "$K_STATE" ] && have node || return 0
  node -e 'try{process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).gwsScopes||"")}catch(e){}' "$K_STATE" 2>/dev/null
}
state_set_scopes(){
  dry_run && return 0
  mkdir -p "${K_STATE%/*}" || return 1
  K_STATE_SCOPES="$1" K_STATE_ROLE="$K_ROLE" node - "$K_STATE" <<'NODE'
const fs=require('fs'),p=process.argv[2];let s={};try{s=JSON.parse(fs.readFileSync(p,'utf8'))}catch(e){}
if(s.role!==process.env.K_STATE_ROLE)s={role:process.env.K_STATE_ROLE,steps:{},gwsScopes:s.gwsScopes||''};
s.gwsScopes=process.env.K_STATE_SCOPES;
const t=p+'.tmp';fs.writeFileSync(t,JSON.stringify(s,null,2)+'\n',{mode:0o600});fs.renameSync(t,p);
NODE
}
state_set(){
  dry_run && return 0
  have node || return 1
  mkdir -p "${K_STATE%/*}" || return 1
  K_STATE_STEP="$1" K_STATE_RESULT="$2" K_STATE_ROLE="$K_ROLE" node - "$K_STATE" <<'NODE'
const fs=require('fs'),p=process.argv[2];let s={};try{s=JSON.parse(fs.readFileSync(p,'utf8'))}catch(e){}
if(s.role!==process.env.K_STATE_ROLE)s={role:process.env.K_STATE_ROLE,steps:{},gwsScopes:s.gwsScopes||''};
s.steps[process.env.K_STATE_STEP]=process.env.K_STATE_RESULT;
s.lastRun=new Date().toISOString();
const t=p+'.tmp';fs.writeFileSync(t,JSON.stringify(s,null,2)+'\n',{mode:0o600});fs.renameSync(t,p);
NODE
}
run_step(){ # name, check-function, action-function
  local name="$1" check_fn="$2" action_fn="$3" result
  if dry_run; then say "予定: $name"; return 0; fi
  if update_only && [ "$name" != hub-update ] && [ "$name" != npm-ci ] && [ "$name" != skills ]; then return 0; fi
  if "$check_fn"; then result=skip; ok "$name は済み";
  elif "$action_fn"; then result=ok; ok "$name 完了";
  else result=fail; warn "$name を完了できませんでした"; fi
  state_set "$name" "$result" || warn 'state.json を書けませんでした'
  [ "$result" != fail ]
}
valid_skill(){ case "$1" in ''|*[!a-zA-Z0-9-]*) return 1;; esac; return 0; }
allow_workspace_repos(){
  local settings="$1/.claude/settings.local.json" repos="$2/repos"
  K_ALLOWED_REPOS="$repos" node - "$settings" <<'NODE'
const fs=require('fs'),p=process.argv[2],repos=process.env.K_ALLOWED_REPOS.replace(/\\/g,'/');
let s={};
if(fs.existsSync(p)){
  try{const raw=fs.readFileSync(p,'utf8');s=raw.trim()?JSON.parse(raw):{}}catch(e){console.error('settings.local.json の JSON が壊れているため変更しません');process.exit(0)}
  if(!s||typeof s!=='object'||Array.isArray(s)){console.error('settings.local.json の形式が正しくないため変更しません');process.exit(0)}
}
if(!s.permissions||typeof s.permissions!=='object'||Array.isArray(s.permissions))s.permissions={};
const dirs=Array.isArray(s.permissions.additionalDirectories)?s.permissions.additionalDirectories:[];
if(dirs.includes(repos))process.exit(0);
s.permissions.additionalDirectories=[...dirs,repos];
const tmp=p+'.tmp';fs.writeFileSync(tmp,JSON.stringify(s,null,2)+'\n',{mode:0o600});fs.renameSync(tmp,p);
NODE
}
copy_skills(){
  local hub="$1" role="$2" list name workspace item
  [ -d "$hub/.claude/skills" ] || return 1
  if [ ! -f "$hub/profiles/$role.json" ]; then return 0; fi
  workspace="$HOME/.config/daimaru-setup/workspaces/$role"
  rm -f "$workspace/.ready" || return 1
  have node || return 1
  list="$(node -e 'try{const a=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).skills;if(!Array.isArray(a)||a.some(x=>typeof x!=="string"||!/^[A-Za-z0-9-]+$/.test(x)))process.exit(2);a.forEach(x=>console.log(x))}catch(e){process.exit(2)}' "$hub/profiles/$role.json")" || return 1
  mkdir -p "$workspace/.claude" || return 1
  rm -f "$workspace/.ready" || return 1
  rm -rf "$workspace/.claude/skills" || return 1
  mkdir -p "$workspace/.claude/skills" || return 1
  for item in "$hub/.claude/"*; do
    [ -e "$item" ] || continue
    [ "${item##*/}" = skills ] && continue
    [ "${item##*/}" = settings.local.json ] && [ -f "$workspace/.claude/settings.local.json" ] && continue
    rm -rf "$workspace/.claude/${item##*/}" || return 1
    cp -R "$item" "$workspace/.claude/${item##*/}" || return 1
  done
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    valid_skill "$name" || return 1
    [ -d "$hub/.claude/skills/$name" ] || return 1
    cp -R "$hub/.claude/skills/$name" "$workspace/.claude/skills/$name" || return 1
  done <<EOF
$list
EOF
  [ ! -f "$hub/CLAUDE.md" ] || cp "$hub/CLAUDE.md" "$workspace/CLAUDE.md" || return 1
  if [ ! -L "$workspace/repos" ] && [ -e "$workspace/repos" ]; then
    warn 'repos が実ディレクトリのため削除せず、ワークスペースを未準備にします'
    return 1
  fi
  if [ -d "$hub/repos" ]; then
    if [ -L "$workspace/repos" ]; then rm "$workspace/repos" || return 1; fi
    ln -s "$hub/repos" "$workspace/repos" || return 1
    allow_workspace_repos "$workspace" "$hub" || return 1
  fi
  : > "$workspace/.ready"
}
role_workspace(){
  if [ -f "$1/profiles/$2.json" ]; then
    [ -f "$HOME/.config/daimaru-setup/workspaces/$2/.ready" ] || return 1
    printf '%s/.config/daimaru-setup/workspaces/%s' "$HOME" "$2"
  else printf '%s' "$1"; fi
}
chrome_extension_state(){
  local root="$1" f
  [ -d "$root" ] || return 1
  while IFS= read -r f; do
    if have node && node -e 'try{let n=require(process.argv[1]).name||"";process.exit(!n.startsWith("__MSG_")&&n.includes("Claude")?0:1)}catch(e){process.exit(1)}' "$f" 2>/dev/null; then return 0; fi
  done < <(find "$root" -path '*/Extensions/*/*/manifest.json' -type f -print 2>/dev/null)
  return 1
}
