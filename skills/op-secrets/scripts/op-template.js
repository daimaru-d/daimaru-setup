#!/usr/bin/env node
// =============================================================================
// op-template.js — 1Password の項目テンプレート（JSON）を作る内部部品
//   op-item-add.sh と op-env-migrate.sh が呼ぶ。テンプレートは標準出力に書き、呼び出し側が
//   そのまま op item create / edit の標準入力へ流す（引数・一時ファイル・画面には値を出さない）。
//
//   node op-template.js login
//       標準入力に NUL 区切りで: title, url, username, password, generate(0|1), totp, [name, value]...
//   node op-template.js env --env FILE --vault V --item N --out-envop F --out-example F --out-summary F
//                           [--existing -] [--overwrite]
//       .env を読み、秘密らしいキーを 1 項目にまとめたテンプレートを標準出力へ。
//       参照だけの .env.op、値を伏せた .env.op.example、キー名と行き先の一覧（値なし）をファイルへ。
//       --existing - のときは標準入力の既存の項目（op item get --reveal の JSON）に足す。
//       既存の値が入っている欄は上書きせず、キー名だけを出して終了コード 5（--overwrite で上書き）。
// =============================================================================
'use strict';
const fs = require('fs');

const BOOL_FLAGS = new Set(['overwrite']);

function die(msg, code) {
  process.stderr.write(msg + '\n');
  process.exit(code || 2);
}

function args(argv) {
  const o = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const k = a.slice(2);
      if (BOOL_FLAGS.has(k)) o[k] = true;
      else { o[k] = argv[i + 1]; i++; }
    } else o._.push(a);
  }
  return o;
}

function fieldUsername(v) { return { id: 'username', type: 'STRING', purpose: 'USERNAME', label: 'username', value: v }; }
function fieldPassword(v) { return { id: 'password', type: 'CONCEALED', purpose: 'PASSWORD', label: 'password', value: v }; }
function fieldCustom(label, v, type) { return { id: label.toLowerCase(), type: type || 'CONCEALED', label, value: v }; }

function sameField(e, f) {
  return (f.purpose && e.purpose === f.purpose) || e.id === f.id || e.label === f.label;
}

// 既存の項目に足す。値が入っている欄を別の値で上書きしそうなら、そのキー名を返す
function merge(existing, tmpl, overwrite, keyOf) {
  if (!existing) return { item: tmpl, conflicts: [] };
  const out = existing;
  out.fields = Array.isArray(out.fields) ? out.fields : [];
  const conflicts = [];
  for (const f of tmpl.fields) {
    const hit = out.fields.find((e) => sameField(e, f));
    if (!hit) { out.fields.push(f); continue; }
    if (hit.value && hit.value !== f.value && !overwrite) { conflicts.push(keyOf(f)); continue; }
    hit.value = f.value;
  }
  if (tmpl.urls && tmpl.urls.length && !(out.urls && out.urls.length)) out.urls = tmpl.urls;
  return { item: out, conflicts };
}

function login() {
  const parts = fs.readFileSync(0).toString('utf8').split('\0');
  const [title, url, username, password, generate, totp] = parts;
  const t = { title, category: 'LOGIN', fields: [fieldUsername(username || '')] };
  if (generate !== '1') t.fields.push(fieldPassword(password || ''));
  if (totp) t.fields.push({ id: 'onetimepassword', type: 'OTP', label: 'one-time password', value: totp });
  for (let i = 6; i + 1 < parts.length; i += 2) {
    if (parts[i]) t.fields.push(fieldCustom(parts[i], parts[i + 1] || ''));
  }
  if (url) t.urls = [{ label: 'website', primary: true, href: url }];
  parts.length = 0;
  process.stdout.write(JSON.stringify(t));
}

// --- .env の分解（lib.sh の ops_parse_env_line と同じ規則） ---
const LINE_RE = /^\s*(export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/;
function parseLine(line) {
  if (!line.trim()) return { type: 'blank' };
  if (line.trim().startsWith('#')) return { type: 'comment' };
  const m = LINE_RE.exec(line);
  if (!m) return { type: 'bad' };
  let v = m[3].replace(/\s+$/, '');
  if (v.length >= 2 && ((v[0] === '"' && v.endsWith('"')) || (v[0] === "'" && v.endsWith("'")))) v = v.slice(1, -1);
  else v = v.replace(/\s#.*$/, '');
  return { type: 'kv', key: m[2], value: v };
}

// lib.sh の ops_is_secret_key と同じ規則（op-run.sh が平文を拒むキー）
function isSecretKey(key) {
  const u = key.toUpperCase();
  if (/PASSWORD|PASSWD|SECRET|TOKEN|CREDENTIAL|PRIVATE|APIKEY|ACCESSKEY/.test(u)) return true;
  return /(^|_)(PASS|KEY)($|_)/.test(u);
}

// 行き先: password / username / concealed / null（平文のまま .env.op に残す）
function kindOf(key, value) {
  const u = key.toUpperCase();
  if (/(^|_)PASS(WORD)?($|_)|PASSWD/.test(u)) return 'password';
  if (isSecretKey(key)) return 'concealed';
  if (/EMAIL|USER|LOGIN/.test(u)) return 'username';
  if (/URL|DSN|WEBHOOK|AUTH|COOKIE|SESSION/.test(u)) return 'concealed';
  if (/:\/\/[^/]*:[^@]*@/.test(value)) return 'concealed'; // URL の中の ID・パスワード
  return null;
}

function env(o) {
  for (const k of ['env', 'vault', 'item', 'out-envop', 'out-example', 'out-summary']) if (!o[k]) die(`--${k} が必要です`);
  let existing = null;
  if (o.existing === '-') {
    try { existing = JSON.parse(fs.readFileSync(0, 'utf8')); } catch (_) { die('既存の項目を読めませんでした'); }
  }
  const lines = fs.readFileSync(o.env, 'utf8').split(/\r?\n/);
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  const bad = [];
  const t = { title: o.item, category: 'LOGIN', fields: [] };
  const header = '# 値は書かない。1Password の「住所」（秘密参照）だけを書く。実行は op-run.sh -- <コマンド>';
  const envop = [header];
  const example = [header];
  const summary = [];
  const keyOfField = new Map();
  let haveUser = false;
  let havePass = false;
  lines.forEach((line, i) => {
    const p = parseLine(line);
    if (p.type === 'bad') { bad.push(i + 1); return; }
    if (p.type === 'comment') return; // コメントには値やメモが書かれていることがあるので写さない
    if (p.type === 'blank') { envop.push(''); example.push(''); return; }
    if (p.value.startsWith('op://')) {
      envop.push(`${p.key}=${p.value}`);
      example.push(`${p.key}=${p.value}`);
      summary.push(`plain\t${p.key}`);
      return;
    }
    const kind = kindOf(p.key, p.value);
    if (!kind) {
      envop.push(`${p.key}=${p.value}`);
      example.push(`${p.key}=<設定値>`);
      summary.push(`plain\t${p.key}`);
      return;
    }
    let f;
    if (kind === 'password' && !havePass) { havePass = true; f = fieldPassword(p.value); }
    else if (kind === 'username' && !haveUser) { haveUser = true; f = fieldUsername(p.value); }
    else f = fieldCustom(p.key, p.value, kind === 'username' ? 'STRING' : 'CONCEALED');
    t.fields.push(f);
    keyOfField.set(f, p.key);
    const ref = `${p.key}=op://${o.vault}/${o.item}/${f.label}`;
    envop.push(ref);
    example.push(ref);
    summary.push(`secret\t${p.key}\t${f.label}`);
  });
  if (bad.length) die(`KEY=値 の形でない行があります: 行 ${bad.join(', ')}`, 3);
  if (!t.fields.length) die('1Password へ移す値（パスワード・ID など）が見つかりませんでした', 4);
  const { item, conflicts } = merge(existing, t, !!o.overwrite, (f) => keyOfField.get(f));
  if (conflicts.length) {
    process.stderr.write(`CONFLICT\t${conflicts.join(',')}\n`);
    process.exit(5);
  }
  fs.writeFileSync(o['out-envop'], envop.join('\n') + '\n');
  fs.writeFileSync(o['out-example'], example.join('\n') + '\n');
  fs.writeFileSync(o['out-summary'], summary.join('\n') + '\n');
  process.stdout.write(JSON.stringify(item));
}

const o = args(process.argv.slice(2));
const mode = o._[0];
if (mode === 'login') login();
else if (mode === 'env') env(o);
else die('使い方: op-template.js login|env ...');
