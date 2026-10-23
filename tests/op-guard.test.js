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

const BLOCK = [
  'op read op://Claude-Automation/andpad/password',
  'op read "op://Claude-Automation/andpad/password"',
  'op item get andpad --vault Claude-Automation',
  'op item get andpad --otp',
  'op --account daimaruenterprise.1password.com item get andpad',
  'op document get secret-file',
  'op signin --raw',
  'op signin --account daimaruenterprise.1password.com --raw',
  'op-claude read op://x/y/z',
  '~/.claude/bin/op-claude item get abc',
  'ls; op read op://a/b/c',
  'echo $(op read op://a/b/c)',
  'bash -c "op item get andpad"',
  'cat .env',
  'cat andpad-browser/.env',
  'less .env.local',
  'head -n 3 .env.production',
  'tail config/.env',
  'Get-Content .env',
  'type .env',
  'strings .env',
  'xxd .env | head',
  'grep -r PASSWORD .env',
  'grep -i password andpad-browser/.env',
  'env',
  'printenv',
  'set',
  'export',
  'declare -x',
  'env | grep ANDPAD',
  'Get-ChildItem env:',
  'gci env:',
  'dir env:',
  'op run --env-file .env.op -- env',
  'op run --env-file .env.op -- printenv',
  'echo $ANDPAD_PASSWORD',
  'echo ${API_KEY}',
  'echo "$OP_SERVICE_ACCOUNT_TOKEN"',
  'printf "%s" $DB_SECRET',
  'Write-Host $env:ANDPAD_PASSWORD',
  'echo %ANDPAD_PASSWORD%',
  'printenv ANDPAD_PASSWORD',
  'security find-generic-password -s daimaru-op-sa -w',
  'security find-internet-password -s example.com -g',
  'security dump-keychain',
  'secret-tool lookup service daimaru-op-sa account me',
  'powershell.exe -Command "Get-Content $env:LOCALAPPDATA\\daimaru-op\\sa-token.dpapi | ConvertTo-SecureString"',
  'cat ~/.config/op/config',
  'cat .op/config',
  'cat ~/.config/daimaru-op/sa-token',
  'op-run.sh -- env',
  'bash ~/.claude/skills/op-secrets/scripts/op-run.sh -- printenv',
  'op-run.sh --env-file .env.op -- set',
];

const PASS = [
  "grep -n 'op read' SKILL.md",
  'grep -n "op item get" skills/op-secrets/SKILL.md',
  'op item list',
  'op item list --vault Claude-Automation --format json',
  'op vault list',
  'op whoami',
  'op --account daimaruenterprise.1password.com whoami',
  'op-run.sh -- node x.mjs',
  'bash ~/.claude/skills/op-secrets/scripts/op-run.sh -- node create-mitsumori-draft.mjs',
  'op run --env-file .env.op -- node x.mjs',
  'cat .env.op',
  'cat .env.example',
  'cat .env.op.example',
  'cat .env.sample',
  'git diff',
  'echo $HOME',
  'echo $DRY_RUN',
  'echo "hello"',
  'set -euo pipefail',
  'export DRY_RUN=1',
  'env DRY_RUN=1 node x.mjs',
  'ls -la',
  'grep -rn PASSWORD src/',
  'cat README.md',
  'security find-generic-password -s daimaru-op-sa',
  'bash ~/.claude/skills/op-secrets/scripts/op-sa-token.sh status',
  'bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh',
  'cd /tmp/set',
  'node --test tests/',
];

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
