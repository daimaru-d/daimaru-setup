#!/usr/bin/env node
// =============================================================================
// settings-merge.js — Claude Code の設定（~/.claude/settings.json）に、op-secrets の見張り（フック）と
//                     禁止リスト（deny）を足す。何度実行しても同じ結果になる（冪等）
//   node settings-merge.js [--check] [--settings PATH] [--skill-dir DIR]
//   --check: 入っていれば終了コード 0、足りなければ何が無いかを出して 2
//   --skill-dir: スキルを実際に置いた場所（install.sh が渡す）。省略時は ~/.claude/skills/op-secrets
// settings.json がシンボリックリンクでも、リンクを壊さずに実体へ書く。
// 書き込む前に settings.json.bak-YYYYMMDDHHMMSS を 1 つ作る。JSON が壊れていたら触らずに 2 で終わる。
// 既存のキー・並び・ほかの設定はそのまま残す（読み込んで足して書く）。
// =============================================================================
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');

// deny は allow より強いので、.env.* をまとめて止めず（.env.op と見本を読めるように）よくある名前を並べる
const DENY = [
  'Read(**/.env)',
  'Read(**/.env.local)',
  'Read(**/.env.*.local)',
  'Read(**/.env.production)',
  'Read(**/.env.staging)',
  'Read(**/.env.test)',
  'Read(**/.env.development)',
  'Read(**/.env.bak)',
  'Edit(**/.env)',
  'Bash(op read:*)',
  'Bash(op item get:*)',
  'Bash(op document get:*)',
  'Bash(op inject:*)',
  'Bash(op run:*)',
  'Bash(security find-generic-password:*)',
  'Bash(security find-internet-password:*)',
];
const MATCHER = 'Bash|PowerShell';

function homeDir() {
  const h = process.platform === 'win32'
    ? (process.env.USERPROFILE || os.homedir())
    : (process.env.HOME || os.homedir());
  return h.replace(/\\/g, '/');
}

function guardPath(skillDir) {
  return `${skillDir.replace(/\\/g, '/').replace(/\/+$/, '')}/scripts/op-guard.js`;
}

function guardCommand(skillDir) {
  return `node "${guardPath(skillDir)}"`;
}

// 同じ command のフックの入れ物（無ければ null）
function findHook(settings, cmd) {
  const pre = settings && settings.hooks && Array.isArray(settings.hooks.PreToolUse) ? settings.hooks.PreToolUse : [];
  return pre.find((e) => e && Array.isArray(e.hooks) && e.hooks.some((h) => h && h.command === cmd)) || null;
}

function missingDeny(settings) {
  const deny = settings && settings.permissions && Array.isArray(settings.permissions.deny) ? settings.permissions.deny : [];
  return DENY.filter((d) => !deny.includes(d));
}

function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function main() {
  const argv = process.argv.slice(2);
  const check = argv.includes('--check');
  const opt = (name) => { const k = argv.indexOf(name); return k >= 0 && argv[k + 1] ? argv[k + 1] : null; };
  const home = homeDir();
  const file = opt('--settings') || path.join(home, '.claude', 'settings.json');
  const skillDir = opt('--skill-dir') || `${home}/.claude/skills/op-secrets`;
  const cmd = guardCommand(skillDir);

  let settings = {};
  let existed = false;
  if (fs.existsSync(file)) {
    existed = true;
    const raw = fs.readFileSync(file, 'utf8');
    if (raw.trim()) {
      try {
        settings = JSON.parse(raw);
      } catch (e) {
        process.stderr.write(`✗ ${file} の JSON が壊れているため、触らずに終わります（直してから再実行してください）\n`);
        return 2;
      }
    }
    if (settings === null || typeof settings !== 'object' || Array.isArray(settings)) {
      process.stderr.write(`✗ ${file} の中身が設定の形（{...}）ではないため、触らずに終わります\n`);
      return 2;
    }
  }

  const hook = findHook(settings, cmd);
  const needHook = !hook;
  const needMatcher = !!hook && hook.matcher !== MATCHER;
  const needDeny = missingDeny(settings);

  if (check) {
    const problems = [];
    if (needHook) problems.push(`見張り（PreToolUse フック）が未登録: ${cmd}`);
    if (needMatcher) problems.push(`見張りの対象が ${MATCHER} になっていません（今: ${hook.matcher}）`);
    if (needDeny.length) problems.push(`禁止リスト（permissions.deny）に足りないもの: ${needDeny.join(', ')}`);
    if (!fs.existsSync(guardPath(skillDir))) problems.push(`見張りの本体がありません: ${guardPath(skillDir)}`);
    if (problems.length) {
      for (const p of problems) process.stdout.write(`${p}\n`);
      return 2;
    }
    process.stdout.write('settings.json: 見張りと禁止リストは登録済み\n');
    return 0;
  }

  if (!needHook && !needMatcher && !needDeny.length) {
    process.stdout.write('settings.json: 変更なし（登録済み）\n');
    return 0;
  }

  if (needHook) {
    if (!settings.hooks || typeof settings.hooks !== 'object' || Array.isArray(settings.hooks)) settings.hooks = {};
    if (!Array.isArray(settings.hooks.PreToolUse)) settings.hooks.PreToolUse = [];
    settings.hooks.PreToolUse.push({ matcher: MATCHER, hooks: [{ type: 'command', command: cmd }] });
  }
  if (needMatcher) hook.matcher = MATCHER;
  if (needDeny.length) {
    if (!settings.permissions || typeof settings.permissions !== 'object' || Array.isArray(settings.permissions)) settings.permissions = {};
    if (!Array.isArray(settings.permissions.deny)) settings.permissions.deny = [];
    settings.permissions.deny.push(...needDeny);
  }

  fs.mkdirSync(path.dirname(file), { recursive: true });
  // シンボリックリンクなら実体に書く（rename で差し替えるとリンクが普通のファイルに変わってしまう）
  const target = existed ? fs.realpathSync(file) : file;
  if (existed) fs.copyFileSync(target, `${file}.bak-${stamp()}`);
  fs.writeFileSync(target, JSON.stringify(settings, null, 2) + '\n');
  process.stdout.write(`settings.json: 見張り${needHook ? 'を登録' : needMatcher ? 'の対象を更新' : 'は登録済み'}・禁止リストに ${needDeny.length} 件追加（${file}）\n`);
  return 0;
}

try {
  process.exitCode = main();
} catch (e) {
  process.stderr.write(`✗ settings.json を更新できませんでした: ${e && e.message ? e.message : e}\n`);
  process.exitCode = 2;
}
