// workspace.js: the workspace root search and the npm package hint.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { SCRIPTS, seedWorkspace, tempDir, runScript } = require('./helpers');
const { findRoot, takeRootArg } = require(path.join(SCRIPTS, 'workspace.js'));

const ws = seedWorkspace('root');
const deep = path.join(ws, '2026_01_01_Example', 'notes');
fs.mkdirSync(deep, { recursive: true });
const outside = tempDir('outside');

function withEnv(value, fn) {
  const saved = process.env.JOBSEARCH_ROOT;
  if (value === undefined) delete process.env.JOBSEARCH_ROOT; else process.env.JOBSEARCH_ROOT = value;
  try { return fn(); } finally {
    if (saved === undefined) delete process.env.JOBSEARCH_ROOT; else process.env.JOBSEARCH_ROOT = saved;
  }
}

test('--root wins over JOBSEARCH_ROOT and the search', () => {
  const args = ['a.yaml', '--root', outside, '--no-docx'];
  const dir = takeRootArg(args);
  assert.deepEqual(args, ['a.yaml', '--no-docx'], '--root and its folder must be removed from the arguments');
  withEnv(ws, () => assert.equal(findRoot(dir, [deep]), path.resolve(outside), 'findRoot must return the --root folder'));
});

test('--root without a folder is an error', () => {
  assert.throws(() => takeRootArg(['--root']), /--root needs a folder/);
});

test('JOBSEARCH_ROOT wins over the search', () => {
  withEnv(outside, () => assert.equal(findRoot(undefined, [deep]), path.resolve(outside),
    'findRoot must return JOBSEARCH_ROOT when no --root is given'));
});

test('the search goes upwards from the start folder', () => {
  withEnv(undefined, () => assert.equal(findRoot(undefined, [deep]), path.resolve(ws),
    'findRoot must find the folder with MyProfile/cv/cv_master.yaml above the start folder'));
});

test('the search tries each start folder in turn (current directory, then the input file)', () => {
  withEnv(undefined, () => assert.equal(findRoot(undefined, [outside, deep]), path.resolve(ws),
    'findRoot must go on to the folder of the input file when the current directory has no workspace'));
});

test('without a workspace the root is the current directory', () => {
  withEnv(undefined, () => assert.equal(findRoot(undefined, [outside]), process.cwd()));
});

test('cv.js --lint finds the workspace upwards from the input file', () => {
  const file = path.join(deep, 'letter.md');
  fs.writeFileSync(file, 'I have built services in Go.\n');
  const r = runScript('cv.js', ['--lint', file], { cwd: outside });
  assert.equal(r.code, 1, `the Go rule of the workspace must fail the lint; output:\n${r.all}`);
  assert.match(r.all, /No experience with Go/);
});

test('a missing npm package prints the install hint', () => {
  const code = `require(${JSON.stringify(path.join(SCRIPTS, 'workspace.js'))}).requireDep('no-such-package-jobsearch')`;
  const m = spawnSync(process.execPath, ['-e', code], { encoding: 'utf8' });
  assert.equal(m.status, 1, 'requireDep must exit with code 1');
  assert.match(m.stderr, /npm package "no-such-package-jobsearch" not found/);
  assert.match(m.stderr, /install-deps\.ps1/, 'the message must name install-deps.ps1');
});
