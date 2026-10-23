// op-guard.js（PreToolUse フック）の「止める／通す」の表。実行: node --test tests/
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const GUARD = path.join(__dirname, '..', 'skills', 'op-secrets', 'scripts', 'op-guard.js');
const HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'op-guard-test-'));

function run(input) {
  const r = spawnSync(process.execPath, [GUARD], {
    input: typeof input === 'string' ? input : JSON.stringify(input),
    env: { ...process.env, HOME, USERPROFILE: HOME },
    encoding: 'utf8',
  });
  return r;
}
function bash(command) {
  return run({ tool_name: 'Bash', tool_input: { command }, session_id: 'test-session', cwd: '/work/dir' });
}

// 表は tests/guard-cases.txt（--- PASS より上が止める、下が通す。# で始まる行は説明）
const CASES = fs.readFileSync(path.join(__dirname, 'guard-cases.txt'), 'utf8').split(/\r?\n/).filter((l) => l && !l.startsWith('# '));
const SEP = CASES.findIndex((l) => l.startsWith('--- PASS'));
const BLOCK = CASES.slice(0, SEP);
const PASS = CASES.slice(SEP + 1);

test('表の件数（止める 25 件以上・通す 25 件以上）', () => {
  assert.ok(BLOCK.length >= 25 && PASS.length >= 25, `${BLOCK.length} / ${PASS.length}`);
});

for (const cmd of BLOCK) {
  test(`止める: ${cmd}`, () => {
    const r = bash(cmd);
    assert.strictEqual(r.status, 2, `exit=${r.status} stderr=${r.stderr}`);
    assert.match(r.stderr, /ブロック（.+）/);
  });
}

for (const cmd of PASS) {
  test(`通す: ${cmd}`, () => {
    const r = bash(cmd);
    assert.strictEqual(r.status, 0, `exit=${r.status} stderr=${r.stderr}`);
    assert.strictEqual(r.stderr, '');
  });
}

test('Bash 以外のツールは通す', () => {
  assert.strictEqual(run({ tool_name: 'Read', tool_input: { file_path: '.env' } }).status, 0);
});

test('PowerShell ツールも見張る（command 以外のキーでも文字列の値をすべて見る）', () => {
  let r = run({ tool_name: 'PowerShell', tool_input: { command: 'Get-Content .env' } });
  assert.strictEqual(r.status, 2);
  r = run({ tool_name: 'PowerShell', tool_input: { script: 'gci env:' } });
  assert.strictEqual(r.status, 2);
  r = run({ tool_name: 'PowerShell', tool_input: { args: { inner: ['Write-Host $env:ANDPAD_PASSWORD'] } } });
  assert.strictEqual(r.status, 2);
  r = run({ tool_name: 'PowerShell', tool_input: { command: 'Get-ChildItem .' } });
  assert.strictEqual(r.status, 0);
});

test('JSON が読めないときは通す（fail-open）', () => {
  assert.strictEqual(run('{not json').status, 0);
  assert.strictEqual(run('').status, 0);
  assert.strictEqual(run({ tool_name: 'Bash', tool_input: { command: 42 } }).status, 0);
});

test('監査ログにはコマンド本文を書かない', () => {
  const r = bash('cat .env # MARKER-SHOULD-NOT-BE-LOGGED');
  assert.strictEqual(r.status, 2);
  const dir = path.join(HOME, '.claude', 'audit');
  const files = fs.readdirSync(dir).filter((f) => /^op-guard-\d{6}\.log$/.test(f));
  assert.strictEqual(files.length, 1);
  const log = fs.readFileSync(path.join(dir, files[0]), 'utf8');
  assert.match(log, /\ttest-session\tBLOCKED\t.+\t\/work\/dir\n/);
  assert.doesNotMatch(log, /MARKER-SHOULD-NOT-BE-LOGGED/);
});

test.after(() => fs.rmSync(HOME, { recursive: true, force: true }));
