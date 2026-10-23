#!/usr/bin/env node
// =============================================================================
// op-template.js — 1Password の項目テンプレート（JSON）を作る内部部品
//   op-item-add.sh と op-env-migrate.sh が呼ぶ。値はファイル（0600）にだけ書き、画面には出さない。
//   1Password へ値を渡すときに引数（プロセス一覧に見える）を使わず、op の --template で渡すため。
//
//   node op-template.js login --out FILE [--existing FILE]
//       標準入力に NUL 区切りで: title, url, username, password, generate(0|1), totp, [name, value]...
//   node op-template.js env --env FILE --vault V --item N --out-template FILE --out-envop FILE [--existing FILE]
//       .env を読み、秘密らしいキーを 1 項目にまとめたテンプレートと、参照だけの .env.op を書く。
//       標準出力にはキー名と行き先だけ（値は出さない）。
// =============================================================================
'use strict';
const fs = require('fs');

function die(msg, code) {
  process.stderr.write(msg + '\n');
  process.exit(code || 2);
}

function args(argv) {
  const o = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      o[a.slice(2)] = argv[i + 1];
      i++;
    } else o._.push(a);
  }
  return o;
}

function writeSecret(path, text) {
  try { fs.unlinkSync(path); } catch (_) { /* 無ければよい */ }
  fs.writeFileSync(path, text, { mode: 0o600 });
}

function readExisting(path) {
  if (!path) return null;
  try { return JSON.parse(fs.readFileSync(path, 'utf8')); } catch (_) { die('既存の項目を読めませんでした'); }
  return null;
}

// 既存の項目に、同じ id / label のフィールドは値を差し替え、無ければ足す
function merge(existing, tmpl) {
  if (!existing) return tmpl;
  const out = existing;
  out.fields = Array.isArray(out.fields) ? out.fields : [];
  for (const f of tmpl.fields) {
    const hit = out.fields.find((e) => (f.purpose && e.purpose === f.purpose) || e.id === f.id || e.label === f.label);
    if (hit) hit.value = f.value;
    else out.fields.push(f);
  }
  if (tmpl.urls && tmpl.urls.length && !(out.urls && out.urls.length)) out.urls = tmpl.urls;
  return out;
}

function fieldUsername(v) { return { id: 'username', type: 'STRING', purpose: 'USERNAME', label: 'username', value: v }; }
function fieldPassword(v) { return { id: 'password', type: 'CONCEALED', purpose: 'PASSWORD', label: 'password', value: v }; }
function fieldCustom(label, v, type) { return { id: label.toLowerCase(), type: type || 'CONCEALED', label, value: v }; }

function login(o) {
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
  writeSecret(o.out, JSON.stringify(merge(readExisting(o.existing), t)));
}

// --- .env の分解（lib.sh の ops_parse_env_line と同じ規則） ---
const LINE_RE = /^\s*(export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/;
function parseLine(line) {
  if (!line.trim() || line.trim().startsWith('#')) return { type: 'skip' };
  const m = LINE_RE.exec(line);
  if (!m) return { type: 'bad' };
  let v = m[3].replace(/\s+$/, '');
  if (v.length >= 2 && ((v[0] === '"' && v.endsWith('"')) || (v[0] === "'" && v.endsWith("'")))) v = v.slice(1, -1);
  else v = v.replace(/\s#.*$/, '');
  return { type: 'kv', key: m[2], value: v };
}

// 秘密らしいキーの行き先: password / concealed / username / null（平文のまま）
function kindOf(key) {
  const u = key.toUpperCase();
  if (/PASS/.test(u)) return 'password';
  if (/SECRET|TOKEN|KEY|CREDENTIAL|PRIVATE/.test(u)) return 'concealed';
  if (/USER|EMAIL|LOGIN/.test(u) || /(^|_)ID$/.test(u)) return 'username';
  return null;
}

function env(o) {
  for (const k of ['env', 'vault', 'item', 'out-template', 'out-envop']) if (!o[k]) die(`--${k} が必要です`);
  const lines = fs.readFileSync(o.env, 'utf8').split(/\r?\n/);
  if (lines.length && lines[lines.length - 1] === '') lines.pop();
  const bad = [];
  const t = { title: o.item, category: 'LOGIN', fields: [] };
  const envop = ['# 値は書かない。1Password の「住所」（秘密参照）だけを書く。実行は op-run.sh -- <コマンド>'];
  const summary = [];
  let haveUser = false;
  let havePass = false;
  lines.forEach((line, i) => {
    const p = parseLine(line);
    if (p.type === 'bad') { bad.push(i + 1); return; }
    if (p.type === 'skip') { envop.push(line); return; }
    const kind = kindOf(p.key);
    if (!kind || p.value.startsWith('op://')) {
      envop.push(line);
      summary.push(`plain\t${p.key}`);
      return;
    }
    let field;
    if (kind === 'password' && !havePass) { havePass = true; field = 'password'; t.fields.push(fieldPassword(p.value)); }
    else if (kind === 'username' && !haveUser) { haveUser = true; field = 'username'; t.fields.push(fieldUsername(p.value)); }
    else { field = p.key; t.fields.push(fieldCustom(p.key, p.value, kind === 'username' ? 'STRING' : 'CONCEALED')); }
    envop.push(`${p.key}=op://${o.vault}/${o.item}/${field}`);
    summary.push(`secret\t${p.key}\t${field}`);
  });
  if (bad.length) die(`KEY=値 の形でない行があります: 行 ${bad.join(', ')}`, 3);
  if (!t.fields.length) die('1Password へ移す値（パスワード・ID など）が見つかりませんでした', 4);
  writeSecret(o['out-template'], JSON.stringify(merge(readExisting(o.existing), t)));
  fs.writeFileSync(o['out-envop'], envop.join('\n') + '\n');
  process.stdout.write(summary.join('\n') + '\n');
}

const o = args(process.argv.slice(2));
const mode = o._[0];
if (mode === 'login') {
  if (!o.out) die('--out が必要です');
  login(o);
} else if (mode === 'env') {
  env(o);
} else {
  die('使い方: op-template.js login|env ...');
}
