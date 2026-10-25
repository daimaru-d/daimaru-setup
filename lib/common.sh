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
check_gws_secret(){
  local f="${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$HOME/.config/gws}/client_secret.json"
  [ -f "$f" ] && chmod 600 "$f" && have node && node -e 'try{let x=require(process.argv[1]);process.exit(x.installed&&x.installed.client_id&&x.installed.client_secret?0:1)}catch(e){process.exit(1)}' "$f" 2>/dev/null
}
install_gws_secret(){
  local dir="${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$HOME/.config/gws}" tmp ref
  have op || { hint '管理者に 1Password の招待を頼んでください'; return 1; }
  ref="$(k_op_ref)" || return 1
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.client_secret.XXXXXX")" || return 1
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  if ! op read "$ref" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; hint '管理者に 1Password の招待を頼んでください'; return 1
  fi
  if ! node -e 'try{let x=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.exit(x.installed&&x.installed.client_id&&x.installed.client_secret?0:1)}catch(e){process.exit(1)}' "$tmp" 2>/dev/null; then
    rm -f "$tmp"; hint '共有 OAuth 設定を確認できません。管理者に 1Password の招待を頼んでください'; return 1
  fi
  mv -f "$tmp" "$dir/client_secret.json"
}
valid_role(){ case "$1" in base|sekkei|togo|yochi|somu-keiri) return 0;; esac; return 1; }
role_select(){
  K_ROLE="${DAIMARU_ROLE:-}"
  if [ -z "$K_ROLE" ]; then
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
state_get(){
  have node || return 1
  node -e 'try {const s=require(process.argv[1]);if(s.role===process.argv[2]) process.stdout.write(s.steps[process.argv[3]]||"")}catch(e){}' "$K_STATE" "$K_ROLE" "$1" 2>/dev/null
}
state_set(){
  dry_run && return 0
  have node || return 1
  mkdir -p "${K_STATE%/*}" || return 1
  K_STATE_STEP="$1" K_STATE_RESULT="$2" K_STATE_ROLE="$K_ROLE" node - "$K_STATE" <<'NODE'
const fs=require('fs'),p=process.argv[2];let s={};try{s=JSON.parse(fs.readFileSync(p,'utf8'))}catch(e){}
if(s.role!==process.env.K_STATE_ROLE)s={role:process.env.K_STATE_ROLE,steps:{}};
s.steps[process.env.K_STATE_STEP]=process.env.K_STATE_RESULT;
s.lastRun=new Date().toISOString();
const t=p+'.tmp';fs.writeFileSync(t,JSON.stringify(s,null,2)+'\n',{mode:0o600});fs.renameSync(t,p);
NODE
}
run_step(){ # name, check-function, action-function
  local name="$1" check_fn="$2" action_fn="$3" result
  if dry_run; then say "予定: $name"; return 0; fi
  if update_only && [ "$name" != hub-update ] && [ "$name" != skills ]; then return 0; fi
  if "$check_fn"; then result=skip; ok "$name は済み";
  elif "$action_fn"; then result=ok; ok "$name 完了";
  else result=fail; warn "$name を完了できませんでした"; fi
  state_set "$name" "$result" || warn 'state.json を書けませんでした'
  [ "$result" != fail ]
}
valid_skill(){ case "$1" in ''|*[!a-zA-Z0-9-]*) return 1;; esac; return 0; }
copy_skills(){
  local hub="$1" role="$2" list name
  [ -d "$hub/.claude/skills" ] || return 1
  if [ ! -f "$hub/profiles/$role.json" ]; then return 0; fi
  have node || return 1
  list="$(node -e 'try{const a=require(process.argv[1]).skills;if(!Array.isArray(a)||a.some(x=>typeof x!=="string"||!/^[A-Za-z0-9-]+$/.test(x)))process.exit(2);a.forEach(x=>console.log(x))}catch(e){process.exit(2)}' "$hub/profiles/$role.json")" || return 1
  mkdir -p "$HOME/.claude/skills" || return 1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    valid_skill "$name" || return 1
    [ -d "$hub/.claude/skills/$name" ] || return 1
    rm -rf "$HOME/.claude/skills/$name" || return 1
    cp -R "$hub/.claude/skills/$name" "$HOME/.claude/skills/$name" || return 1
  done <<EOF
$list
EOF
}
chrome_extension_state(){
  local root="$1" f
  [ -d "$root" ] || return 1
  while IFS= read -r f; do
    if have node && node -e 'try{let n=require(process.argv[1]).name||"";process.exit(!n.startsWith("__MSG_")&&n.includes("Claude")?0:1)}catch(e){process.exit(1)}' "$f" 2>/dev/null; then return 0; fi
  done < <(find "$root" -path '*/Extensions/*/*/manifest.json' -type f -print 2>/dev/null)
  return 1
}
