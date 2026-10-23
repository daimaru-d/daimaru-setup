#!/usr/bin/env node
// =============================================================================
// op-guard.js — Claude Code の見張り（PreToolUse フック・matcher=Bash|PowerShell）
// Claude が打とうとしたコマンドの文字列を見て、パスワードなどの値を画面に出すものだけ止める（exit 2）。
//   - 1Password の値の表示（op read / op item get / op document get / op inject / op signin --raw /
//     op run --no-masking / op-claude read）
//   - .env の表示（cat .env、grep … .env、< .env など。.env.op / .env.example / .env.sample などは通す）
//   - 環境変数の一覧表示（env / printenv / set / export 単体、echo $PASSWORD、node -e で process.env など）
//   - OS の金庫からの読み出し（security find-*-password -w、secret-tool lookup、DPAPI の復号）
//   - 1Password CLI の設定フォルダ・保管したトークンの表示
// 値を使う処理は op-run.sh（op run）か、値を出さないスクリプトの中で行う。スクリプトの中の呼び出しは止めない。
// 使えなくなるのを避けるため、JSON が読めない・想定外の例外のときは通す（exit 0）。
// 監査ログ: ~/.claude/audit/op-guard-YYYYMM.log（時刻・session_id・BLOCKED・理由・cwd。コマンド本文は書かない）
// =============================================================================
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

// 区切り（行頭・; & | ( $( ` 改行・bash -c "）の直後だけを「コマンドの始まり」とみなす。
// grep 'op read' のような検索文字列では止めない。
const CMD_START = String.raw`(?:^\s*|[;&|(\x60{\n]\s*|\$\(\s*|\s-c\s+["']?\s*)`;
// コマンドの前置き: command / exec / time / sudo / nohup / builtin / env（オプション付き）/ FOO=1 の代入
const WRAP = String.raw`(?:(?:command|exec|time|sudo|nohup|builtin|doas)\s+(?:-\S+\s+)*`
  + String.raw`|env(?:\s+-[A-Za-z-]+(?:\s+[A-Za-z_][A-Za-z0-9_]*)?)*\s+(?=\S)(?![A-Za-z_][A-Za-z0-9_]*=)`
  + String.raw`|[A-Za-z_][A-Za-z0-9_]*=[^\s;&|]*\s+)*`;
// /opt/homebrew/bin/op のようなパス付き
const PATHPFX = String.raw`(?:[^\s;&|'"]*[\\/])?`;
const PRE = CMD_START + WRAP + PATHPFX;
const PRE_NO_WRAP = CMD_START + PATHPFX;

const OP = String.raw`(?:op-claude|op)(?:\.exe)?`;
// op の前置きフラグ（--account X など）。値としてサブコマンド名は取らない
const SUBCMDS = 'read|items?|document|signin|run|inject|get|share|vault|whoami';
const OP_FLAGS = String.raw`(?:\s+--?[A-Za-z][\w-]*(?:=\S+|\s+(?!-)(?!(?:${SUBCMDS})\b)[^\s;&|]+)?)*`;
const END = String.raw`(?=\s|$|[;&|)\x60'"])`;
const SEG_END = String.raw`\s*(?=$|[;&|)\x60\n])`;

const VIEW = String.raw`(?:cat|less|more|head|tail|bat|type|Get-Content|gc|strings|xxd|od|nl|sed|awk|gawk|tac|rev|base64`
  + String.raw`|cut|paste|diff|dd|cp|xargs|vi|vim|nvim|nano|view|git\s+(?:[^\s;&|]+\s+)*?diff)`;
// .env / .env.local / .env.local.bak / .env* など。直前は行頭・/・\・空白・引用符・=・< だけを区切りとみなす
// （app.env や .env.ts、.envrc は止めない）。.env.op / .env.example / .env.sample などの見本は通す
const ENV_OK = String.raw`(?:op|example|op\.example|sample|template|ts|tsx|js|jsx|mjs|cjs|d\.ts|py|rb|go|md)`;
const ENV_B = String.raw`(?=$|[\s'"\x60;&|)<>])`;
const ENV_CORE = String.raw`(?:\.env(?!\.${ENV_OK}${ENV_B})(?:\.[A-Za-z0-9_.*-]+|\*)?|\.e(?:nv?)?\*)${ENV_B}`;
const ENV_TOKEN = String.raw`(?<=^|[\s'"/\\=<])` + ENV_CORE;
// 秘密らしい変数名（語の区切りで判定。$KEYBOARD・$PASSAGE・$MONKEY_PATH は対象外）
const SECRET_WORDS = String.raw`(?:PASS(?:WORD)?|PASSWD|SECRET|TOKEN|KEY|CREDENTIALS?|APIKEY|PRIVATE)`;
const SECRET_VAR = String.raw`(?:[A-Za-z0-9]+_)*${SECRET_WORDS}(?:_[A-Za-z0-9]+)*(?![A-Za-z0-9_])`;
const DUMP_CMD = String.raw`(?:env|printenv|set|export)`;
const INTERP = String.raw`(?:sh|bash|zsh|dash|node|deno|bun|python[0-9.]*|ruby|perl|php|pwsh|powershell)(?:\.exe)?`;
const INLINE = String.raw`\s+(?:-[A-Za-z]*[cep]\b|--eval\b|--print\b|-Command\b)`;

const ALT_OP = '値が要る処理は op-run.sh -- <コマンド> で動かしてください（値は環境変数で渡り、画面では伏せ字になります）。'
  + ' 項目があるかどうかは op item list で確認できます。';
const ALT_ENV = '.env の中身は表示しません。キー名を知りたいときは .env.op / .env.example を見てください。'
  + ' 平文の .env は op-env-migrate.sh で 1Password へ移せます。';
const ALT_DUMP = '環境変数の一覧や秘密の値は表示しません。値が入っているかを確かめたいときは、'
  + ' [ -n "$変数名" ] && echo あり のように「ある/ない」だけを出してください。';
const ALT_SCRIPT = 'op-run.sh -- の後に sh -c / node -e などのその場のスクリプトは渡せません。スクリプトはファイルにして渡してください。';
const ALT_VAULT = 'OS の金庫の値は表示しません。無人実行のトークンは op-sa-token.sh status で「あり/なし」だけ確認できます。';

const R = (s, f) => new RegExp(s, f || '');
const RULES = [
  ['1Password の値の表示',
    R(PRE + OP + OP_FLAGS + String.raw`\s+(?:read|inject|items?` + OP_FLAGS + String.raw`\s+(?:get|share)|document` + OP_FLAGS + String.raw`\s+get)\b`), ALT_OP],
  ['1Password のセッションの表示', R(PRE + OP + OP_FLAGS + String.raw`\s+signin\b[^\n;&|]*\s--raw\b`), ALT_OP],
  ['op run の伏せ字の解除', R(PRE + OP + OP_FLAGS + String.raw`\s+run\b[^\n;&|]*--no-masking(?!=false)\b`), ALT_OP],
  ['op run での環境変数の表示',
    R(PRE + OP + OP_FLAGS + String.raw`\s+run\b[^\n;&|]*?\s--\s+` + WRAP + PATHPFX + '(?:' + DUMP_CMD + END + '|' + INTERP + INLINE + ')'), ALT_DUMP],
  ['op-run.sh での環境変数の表示・その場のスクリプト',
    R(PRE + String.raw`(?:(?:bash|sh)\s+)?` + PATHPFX + String.raw`op-run(?:\.sh)?\b[^\n;&|]*?\s--\s+` + PATHPFX
      + '(?:' + DUMP_CMD + END + '|' + INTERP + INLINE + ')'), ALT_SCRIPT],
  ['.env の表示', R(PRE + VIEW + String.raw`\b[^\n;&|]*?` + ENV_TOKEN, 'i'), ALT_ENV],
  ['.env の検索', R(PRE + String.raw`(?:grep|egrep|fgrep|zgrep|rg|ag|ack|findstr|Select-String|sls)\b[^\n;&|]*?` + ENV_TOKEN, 'i'), ALT_ENV],
  ['秘密の検索（カレント全体）',
    R(PRE + String.raw`(?:grep|egrep|rg)\b(?=[^\n;&|]*\s-[A-Za-z]*[rR])(?=[^\n;&|]*` + SECRET_WORDS + String.raw`)[^\n;&|]*\s(?:\.|\./|~|\$HOME)/?\s*(?=$|[;&|)\n])`, 'i'), ALT_ENV],
  ['.env からの読み込み（リダイレクト）', R(String.raw`(?<!<)<\s*(?:[^\s;&|'"<>]*[\\/])?` + ENV_CORE), ALT_ENV],
  ['その場のスクリプトでの .env・環境変数の表示',
    R(PRE + INTERP + INLINE + String.raw`[^\n]*?(?:` + ENV_TOKEN + String.raw`|process\.env|os\.environ|os\.getenv|getenv|ENV\[|\$env:|environ\b)`), ALT_DUMP],
  ['環境変数の一覧表示',
    R(PRE_NO_WRAP + String.raw`(?:env(?:\s+-u\s*[A-Za-z_][A-Za-z0-9_]*|\s+--unset[= ]\S+|\s+-[0i]+)*|printenv|set|export(?:\s+-p)?|declare\s+-[A-Za-z]*[xp][A-Za-z]*|typeset\s+-[xp]|compgen\s+-[ev]|(?:Get-ChildItem|gci|dir|ls)\s+env:\\?)` + SEG_END, 'i'),
    ALT_DUMP],
  ['環境変数の一覧表示', R(PRE_NO_WRAP + String.raw`env\s+-0\b`), ALT_DUMP],
  ['環境変数の一覧表示', R(String.raw`/proc/[^\s/]+/environ\b`), ALT_DUMP],
  ['秘密の環境変数の表示', R(PRE + String.raw`printenv\s+(?:-\S+\s+)*` + SECRET_VAR, 'i'), ALT_DUMP],
  ['秘密の環境変数の表示',
    R(PRE + String.raw`(?:echo|printf|print|Write-Host|Write-Output)\b[^\n;&|]*(?:\$\{!|\$\{?` + SECRET_VAR + String.raw`|\$env:` + SECRET_VAR + '|%' + SECRET_VAR + '%)', 'i'), ALT_DUMP],
  ['秘密の環境変数の表示', R(String.raw`<<<\s*["']?\$\{?` + SECRET_VAR, 'i'), ALT_DUMP],
  ['無人実行のトークンの読み込み', R(PRE + String.raw`(?:source|\.)\s+[^\n;&|]*op-sa-token\.sh\b|\bops_sa_load\b`), ALT_VAULT],
  ['キーチェーンの秘密の読み出し',
    R(PRE + String.raw`security\s+find-(?:generic|internet)-password\b[^\n;&|]*\s-[a-zA-Z]*[wg][a-zA-Z]*\b`), ALT_VAULT],
  ['キーチェーンの全件出力', R(PRE + String.raw`security\s+dump-keychain\b`), ALT_VAULT],
  ['secret-tool の値の読み出し', R(PRE + String.raw`secret-tool\s+lookup\b`), ALT_VAULT],
  ['1Password CLI の設定・トークンの表示',
    R(PRE + VIEW + String.raw`\b[^\n;&|]*(?:\.config[\\/]op[\\/]|[\s'"\\/=~]\.op[\\/]|daimaru-op[\\/]sa-token\b)`, 'i'), ALT_VAULT],
];

// DPAPI のトークンファイルを復号する行（順番を問わず両方を含む）
function dpapiDecrypt(cmd) {
  return /sa-token\.dpapi/i.test(cmd) && /ConvertTo-SecureString/i.test(cmd);
}

// 引用符とバックスラッシュを外した形（"op" read・'op' read・\op read・op\ read を素の形にそろえる）
function normalize(cmd) {
  return cmd.replace(/\\(.)/g, '$1').replace(/["']/g, '');
}

function findRule(cmd) {
  const forms = [cmd];
  const n = normalize(cmd);
  if (n !== cmd) forms.push(n);
  for (const c of forms) {
    for (const [label, rx, alt] of RULES) {
      if (rx.test(c)) return { label, alt };
    }
  }
  if (dpapiDecrypt(cmd)) return { label: '保管したトークンの復号', alt: ALT_VAULT };
  return null;
}

// 検査する文字列: Bash は command、PowerShell は command か、tool_input の文字列の値をすべてつないだもの
function commandOf(data) {
  const ti = data.tool_input || {};
  if (data.tool_name === 'Bash' && typeof ti.command === 'string') return ti.command;
  const parts = [];
  const walk = (v) => {
    if (typeof v === 'string') parts.push(v);
    else if (Array.isArray(v)) v.forEach(walk);
    else if (v && typeof v === 'object') Object.values(v).forEach(walk);
  };
  walk(ti);
  return parts.join('\n');
}

function clean(s) {
  return String(s == null ? '' : s).replace(/[\t\r\n]+/g, ' ');
}

function audit(data, label) {
  try {
    const dir = path.join(os.homedir(), '.claude', 'audit');
    fs.mkdirSync(dir, { recursive: true });
    const now = new Date();
    const ym = `${now.getUTCFullYear()}${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
    const ts = now.toISOString().replace(/\.\d{3}Z$/, 'Z');
    const cwd = data.cwd || process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const line = [ts, clean(data.session_id || 'unknown'), 'BLOCKED', clean(label), clean(cwd)].join('\t') + '\n';
    fs.appendFileSync(path.join(dir, `op-guard-${ym}.log`), line);
  } catch (_) { /* ログが書けなくても判定は変えない */ }
}

function main() {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  } catch (_) {
    return 0;
  }
  if (!data || (data.tool_name !== 'Bash' && data.tool_name !== 'PowerShell')) return 0;
  const cmd = commandOf(data);
  if (typeof cmd !== 'string' || !cmd) return 0;
  const hit = findRule(cmd);
  if (!hit) return 0;
  audit(data, hit.label);
  process.stderr.write(`ブロック（${hit.label}）: パスワードなどの秘密の値を画面に出すコマンドは使えません（op-secrets）。\n`);
  process.stderr.write(`${hit.alt}\n`);
  return 2;
}

if (require.main === module) {
  let code = 0;
  try { code = main(); } catch (_) { code = 0; }
  process.exitCode = code;
}

module.exports = { findRule, normalize };
