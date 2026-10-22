// Shared helpers of the jobsearch-kit script tests (node --test).
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const REPO = path.resolve(__dirname, '..', '..', '..', '..');
const CONFIG = JSON.parse(fs.readFileSync(path.join(REPO, 'tests', 'jobsearch-kit', 'config.json'), 'utf8'));
const PLUGIN = path.join(REPO, CONFIG.plugin);
const SCRIPTS = path.join(PLUGIN, 'scripts');
const SEED = path.join(REPO, CONFIG.seed);
const EXPECTED = path.join(__dirname, 'expected');

const { requireDep, depsDir } = require(path.join(SCRIPTS, 'workspace.js'));
const YAML = requireDep('yaml');

// A new empty folder under %TEMP%\jobsearch-tests\unit, removed when the process exits.
function tempDir(name) {
  const base = path.join(os.tmpdir(), 'jobsearch-tests', 'unit');
  fs.mkdirSync(base, { recursive: true });
  const dir = fs.mkdtempSync(path.join(base, `${name}-`));
  process.on('exit', () => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

// A copy of the seed workspace in a temporary folder.
function seedWorkspace(name = 'ws') {
  const dir = tempDir(name);
  fs.cpSync(SEED, dir, { recursive: true });
  return dir;
}

// Runs a plugin script with node. The environment never carries JOBSEARCH_ROOT unless the test sets it.
function runScript(script, args, { cwd, env = {} } = {}) {
  const base = { ...process.env };
  delete base.JOBSEARCH_ROOT;
  const r = spawnSync(process.execPath, [path.join(SCRIPTS, script), ...args], {
    cwd, env: { ...base, ...env }, encoding: 'utf8',
  });
  return { code: r.status, out: r.stdout, err: r.stderr, all: r.stdout + r.stderr };
}

// The text of word/document.xml of a .docx file.
async function docxXml(file) {
  const JSZip = require(require.resolve('jszip', { paths: [depsDir, SCRIPTS] }));
  const zip = await JSZip.loadAsync(fs.readFileSync(file));
  return zip.file('word/document.xml').async('string');
}

// The paragraphs of a .docx: plain text of each <w:p>, and whether it has a bold run.
async function docxParagraphs(file) {
  const xml = await docxXml(file);
  return [...xml.matchAll(/<w:p[ >][\s\S]*?<\/w:p>/g)].map(([p]) => ({
    text: [...p.matchAll(/<w:t[^>]*>([^<]*)<\/w:t>/g)].map((m) => m[1]).join(''),
    breaks: (p.match(/<w:br\/>/g) || []).length,
    bold: [...p.matchAll(/<w:r>(?:(?!<\/w:r>)[\s\S])*?<w:b\/>(?:(?!<\/w:r>)[\s\S])*?<w:t[^>]*>([^<]*)<\/w:t>/g)].map((m) => m[1]),
  }));
}

module.exports = { REPO, PLUGIN, SCRIPTS, SEED, EXPECTED, YAML, tempDir, seedWorkspace, runScript, docxXml, docxParagraphs };
