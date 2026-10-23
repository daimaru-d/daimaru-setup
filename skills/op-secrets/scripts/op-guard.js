#!/usr/bin/env node
// =============================================================================
// op-guard.js — Claude Code の見張り（PreToolUse フック・matcher=Bash）
// Claude が Bash で打とうとしたコマンドの文字列を見て、パスワードなどの値を画面に出すものだけ止める（exit 2）。
//   - 1Password の値の表示（op read / op item get / op document get / op signin --raw / op-claude read）
//   - .env の表示（cat .env など。.env.op / .env.example / .env.op.example / .env.sample は通す）
//   - 環境変数の一覧表示（env / printenv / set / export 単体、echo $PASSWORD など）
//   - OS の金庫からの読み出し（security find-*-password -w、secret-tool lookup、DPAPI の復号）
//   - 1Password CLI の設定フォルダの表示
// 値を使う処理は op-run.sh（op run）か、値を出さないスクリプトの中で行う。スクリプトの中の呼び出しは止めない。
// 使えなくなるのを避けるため、JSON が読めない・想定外の例外のときは通す（exit 0）。
// 監査ログ: ~/.claude/audit/op-guard-YYYYMM.log（時刻・session_id・BLOCKED・理由・cwd。コマンド本文は書かない）
// =============================================================================
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

// 区切り（行頭・; & | ( $( ` 改行・bash -c "・パスの /）の直後に来たときだけ「コマンド」とみなす。
// grep 'op read' のような検索文字列では止めない。
const CMD_START_NO_SLASH = String.raw`(?:^\s*|[;&|(\x60\n]\s*|\$\(\s*|-c\s+["']\s*)`;
const CMD_START = String.raw`(?:${CMD_START_NO_SLASH}|/)`;
const OP = String.raw`(?:op-claude|op)(?:\.exe)?`;
// op の前置きフラグ（--account X など）。値として read / item などのサブコマンド名は取らない
const OP_FLAGS = String.raw`(?:\s+--?[A-Za-z][\w-]*(?:=\S+|\s+(?!-)(?!(?:read|item|document|signin|run)\b)[^\s;&|]+)?)*`;
const END = String.raw`(?=\s|$|[;&|)\x60])`;
const SEG_END = String.raw`\s*(?=$|[;&|)\x60\n])`;
const VIEW = String.raw`(?:cat|less|more|head|tail|bat|type|Get-Content|gc|strings|xxd|od|nl)`;
// .env / .env.local など。.env.op / .env.example / .env.sample（と .env.op.example）は除く
const ENV_TOKEN = String.raw`\.env(?:\.(?!(?:op|example|sample)(?=$|[\s'"\x60;&|)]))[A-Za-z0-9_-]+)?(?=$|[\s'"\x60;&|)])`;
const SECRET_WORD = String.raw`(?:PASS|SECRET|TOKEN|KEY|CREDENTIAL)`;
const SECRET_VAR = String.raw`[A-Za-z0-9_]*${SECRET_WORD}[A-Za-z0-9_]*`;
const DUMP_CMD = String.raw`(?:env|printenv|set|export)`;

const ALT_OP = '値が要る処理は op-run.sh -- <コマンド> で動かしてください（値は環境変数で渡り、画面では伏せ字になります）。'
  + ' 項目があるかどうかは op item list で確認できます。';
const ALT_ENV = '.env の中身は表示しません。キー名を知りたいときは .env.op / .env.example を見てください。'
  + ' 平文の .env は op-env-migrate.sh で 1Password へ移せます。';
const ALT_DUMP = '環境変数の一覧や秘密の値は表示しません。値が入っているかを確かめたいときは、'
  + ' [ -n "$変数名" ] && echo あり のように「ある/ない」だけを出してください。';
const ALT_VAULT = 'OS の金庫の値は表示しません。無人実行のトークンは op-sa-token.sh status で「あり/なし」だけ確認できます。';

const RULES = [
  ['1Password の値の表示', new RegExp(CMD_START + OP + OP_FLAGS + String.raw`\s+(?:read|item\s+get|document\s+get)\b`), ALT_OP],
  ['1Password のセッションの表示', new RegExp(CMD_START + OP + OP_FLAGS + String.raw`\s+signin\b[^\n;&|]*\s--raw\b`), ALT_OP],
  ['op run での環境変数の一覧表示', new RegExp(CMD_START + OP + OP_FLAGS + String.raw`\s+run\b[^\n;&|]*\s--\s+` + DUMP_CMD + END), ALT_DUMP],
  ['op-run.sh での環境変数の一覧表示',
    new RegExp(CMD_START + String.raw`(?:(?:bash|sh)\s+)?(?:[^\s;&|]*/)?op-run(?:\.sh)?[^\n;&|]*\s--\s+` + DUMP_CMD + END), ALT_DUMP],
  ['.env の表示', new RegExp(CMD_START + VIEW + String.raw`\b[^\n;&|]*?` + ENV_TOKEN, 'i'), ALT_ENV],
  ['.env からの秘密の検索',
    new RegExp(CMD_START + String.raw`(?:grep|egrep|fgrep|rg|findstr|Select-String|sls)\b(?=[^\n;&|]*` + SECRET_WORD
      + String.raw`)(?=[^\n;&|]*?` + ENV_TOKEN + ')', 'i'), ALT_ENV],
  ['環境変数の一覧表示',
    // 「cd /path/set」のような誤検知を避けるため、ここだけ / の直後はコマンド開始とみなさない
    new RegExp(CMD_START_NO_SLASH + String.raw`(?:env|printenv|set|export|declare\s+-[A-Za-z]*[xp][A-Za-z]*|typeset\s+-x|(?:Get-ChildItem|gci|dir|ls)\s+env:\\?)` + SEG_END, 'i'),
    ALT_DUMP],
  ['秘密の環境変数の表示', new RegExp(CMD_START + String.raw`printenv\s+[^\n;&|]*\b` + SECRET_VAR, 'i'), ALT_DUMP],
  ['秘密の環境変数の表示',
    new RegExp(CMD_START + String.raw`(?:echo|printf|print|Write-Host|Write-Output)\b[^\n;&|]*(?:\$\{?|\$env:|%)` + SECRET_VAR, 'i'), ALT_DUMP],
  ['キーチェーンの秘密の読み出し',
    new RegExp(CMD_START + String.raw`security\s+find-(?:generic|internet)-password\b[^\n;&|]*\s-[a-zA-Z]*[wg]\b`), ALT_VAULT],
  ['キーチェーンの全件出力', new RegExp(CMD_START + String.raw`security\s+dump-keychain\b`), ALT_VAULT],
  ['secret-tool の値の読み出し', new RegExp(CMD_START + String.raw`secret-tool\s+lookup\b`), ALT_VAULT],
  ['1Password CLI の設定・トークンの表示',
    new RegExp(CMD_START + VIEW + String.raw`\b[^\n;&|]*(?:\.config[\\/]op[\\/]|[\s'"\\/=~]\.op[\\/]|daimaru-op[\\/]sa-token\b)`, 'i'), ALT_VAULT],
];

// DPAPI のトークンファイルを復号する行（順番を問わず両方を含む）
function dpapiDecrypt(cmd) {
  return /sa-token\.dpapi/i.test(cmd) && /ConvertTo-SecureString/i.test(cmd);
}

function findRule(cmd) {
  for (const [label, rx, alt] of RULES) {
    if (rx.test(cmd)) return { label, alt };
  }
  if (dpapiDecrypt(cmd)) return { label: '保管したトークンの復号', alt: ALT_VAULT };
  return null;
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
  if (!data || data.tool_name !== 'Bash') return 0;
  const cmd = data.tool_input && data.tool_input.command;
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

module.exports = { findRule };
