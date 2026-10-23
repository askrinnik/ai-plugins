// Template consistency: every CV claim of the seed master is backed by the seed facts (see template-claims.yaml).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { SEED, PLUGIN, YAML, tempDir, runScript } = require('./helpers');

const CLAIMS_FILE = path.join(__dirname, 'template-claims.yaml');

// The text units of the master, keyed as in template-claims.yaml.
function masterUnits(master) {
  const units = { 'header.name': master.header.name };
  for (const c of master.header.contacts) units[`header.contacts.${c.id}`] = c.text;
  for (const [id, t] of Object.entries(master.titles || {})) units[`titles.${id}`] = t;
  for (const s of master.sections) {
    const add = (key, text) => { units[`${s.id}.${key}`] = text; };
    switch (s.kind) {
      case 'text': Object.entries(s.variants).forEach(([id, t]) => add(id, [].concat(t).join(' '))); break;
      case 'list': s.items.forEach((i) => add(i.id, i.text)); break;
      case 'groups': s.groups.forEach((g) => add(g.id, `${g.label}: ${g.text}`)); break;
      case 'jobs':
        for (const j of s.jobs) {
          add(j.id, `${j.title} | ${j.dates} | ${j.company}`);
          j.bullets.forEach((b) => add(`${j.id}.${b.id}`, b.text));
        }
        break;
      case 'projects': s.projects.forEach((p) => add(p.id, JSON.stringify(p))); break;
      case 'paras': s.paras.forEach((t, i) => add(String(i), t)); break;
      default: assert.fail(`unknown section kind "${s.kind}" in section "${s.id}"`);
    }
  }
  return units;
}

// The empty workspace template of the plugin (used by init-workspace): no person's data, every file parses, and the
// full CV builds from the placeholders.
test('the plugin template is an empty skeleton that builds', () => {
  const skeleton = path.join(PLUGIN, 'templates', 'workspace');
  const problems = [];
  const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]));
  for (const file of walk(skeleton)) {
    const text = fs.readFileSync(file, 'utf8');
    for (const mark of ['Jordan', 'Example Payments', 'Sample Retail', 'Lisbon']) {
      if (text.includes(mark)) problems.push(`${path.relative(skeleton, file)}: "${mark}"`);
    }
    if (/\.ya?ml$/.test(file)) YAML.parse(text);
  }
  assert.deepEqual(problems, [], `the empty template holds data of a person:\n  ${problems.join('\n  ')}`);
  const ws = tempDir('skeleton');
  fs.cpSync(skeleton, ws, { recursive: true });
  const r = runScript('cv.js', ['MyProfile/cv/profile_full.yaml', '--no-docx'], { cwd: ws });
  assert.equal(r.code, 0, `the skeleton full CV does not build:\n${r.all}`);
});

const loose =(t) => String(t).replace(/\s+/g, ' ').toLowerCase();

test('every CV claim of the template master is backed by the template facts', () => {
  const master = YAML.parse(fs.readFileSync(path.join(SEED, 'MyProfile/cv/cv_master.yaml'), 'utf8'));
  const facts = loose(fs.readFileSync(path.join(SEED, 'MyProfile/candidate_facts.md'), 'utf8'));
  const claims = YAML.parse(fs.readFileSync(CLAIMS_FILE, 'utf8'));
  const units = masterUnits(master);
  const problems = [];
  for (const [key, text] of Object.entries(units)) {
    if (!claims[key]) problems.push(`${key}: no backing facts listed in template-claims.yaml for "${text}"`);
  }
  for (const [key, phrases] of Object.entries(claims)) {
    if (!(key in units)) problems.push(`${key}: listed in template-claims.yaml but not in the master`);
    for (const p of phrases) {
      if (!facts.includes(loose(p))) problems.push(`${key}: "${p}" is not in candidate_facts.md`);
    }
  }
  assert.deepEqual(problems, [], `template claims without facts:\n  ${problems.join('\n  ')}`);
});
