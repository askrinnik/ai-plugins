// cv.js: the template full CV, every section kind, the wording rules and the error messages.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { SCRIPTS, EXPECTED, YAML, seedWorkspace, tempDir, runScript } = require('./helpers');
const { resolve, toMarkdown, markdownUnits } = require(path.join(SCRIPTS, 'cv.js'));

// To accept a deliberate change of the template CV, run Test-Scripts.ps1 -UpdateExpected (or set UPDATE_EXPECTED=1).
test('the template full CV builds and its .md matches the stored expected file', () => {
  const ws = seedWorkspace('full');
  const r = runScript('cv.js', ['MyProfile/cv/profile_full.yaml'], { cwd: ws });
  assert.equal(r.code, 0, `build failed:\n${r.all}`);
  const profile = YAML.parse(fs.readFileSync(path.join(ws, 'MyProfile/cv/profile_full.yaml'), 'utf8'));
  const base = path.join(ws, 'MyProfile', 'cv', profile.output);
  assert.ok(fs.existsSync(`${base}.docx`), 'the .docx must be written too');
  const md = fs.readFileSync(`${base}.md`, 'utf8');
  const expectedFile = path.join(EXPECTED, `${profile.output}.md`);
  if (process.env.UPDATE_EXPECTED === '1') fs.writeFileSync(expectedFile, md);
  // A checkout with core.autocrlf may turn the stored file to CRLF.
  assert.equal(md, fs.readFileSync(expectedFile, 'utf8').replace(/\r\n/g, '\n'),
    `${profile.output}.md differs from ${expectedFile}. If the template changed on purpose, run Test-Scripts.ps1 -UpdateExpected`);
});

const MASTER = {
  header: {
    name: 'Casey Example',
    contacts: [
      { id: 'email', label: 'E', text: 'casey@example.com', url: 'mailto:casey@example.com' },
      { id: 'phone', label: 'T', text: '+000 1' },
      { id: 'city', label: 'Location', text: 'Porto' },
    ],
  },
  titles: { dev: 'Backend Developer' },
  sections: [
    { id: 'summary', heading: 'Summary', kind: 'text', variants: { default: 'Default summary.', short: ['First para.', 'Second para.'] } },
    { id: 'soft', heading: 'Skills', kind: 'list', items: [{ id: 'a', text: 'Alpha' }, { id: 'b', text: 'Beta' }] },
    { id: 'key', heading: 'Key Skills', kind: 'groups', groups: [{ id: 'be', label: 'Backend', text: 'Java' }, { id: 'db', label: 'Data', text: 'SQL' }] },
    {
      id: 'work',
      heading: 'Work',
      kind: 'jobs',
      jobs: [
        {
          id: 'j1',
          title: 'Engineer',
          dates: '2020 to now',
          company: 'One Ltd',
          bullets: [
            { id: 'x', tags: ['api'], group: 'APIs', text: 'Built **the API**.' },
            { id: 'y', tags: ['ops'], group: 'Ops', text: 'Ran the jobs.' },
          ],
        },
        { id: 'j2', title: 'Developer', dates: '2015 to 2020', company: 'Two SA', bullets: [{ id: 'z', tags: ['api'], text: 'Wrote services.' }] },
      ],
    },
    {
      id: 'proj',
      heading: 'Projects',
      kind: 'projects',
      projects: [{
        id: 'p',
        title: 'Demo',
        paras: ['A demo.'],
        features: [{ text: 'Features', items: ['One', 'Two'] }],
        stack: ['Java', 'SQL'],
        role: 'Sole developer',
        link: { text: 'github.com/example/demo', url: 'https://github.com/example/demo' },
      }],
    },
    { id: 'edu', heading: 'Education', kind: 'paras', paras: ['BSc, 2015.'] },
  ],
};

const build = (profile) => toMarkdown(resolve(MASTER, profile));

test('every section kind renders', () => {
  const md = build({
    title: 'dev',
    sections: [
      { id: 'summary', variant: 'short' },
      { id: 'soft', inline: true },
      { id: 'key', groups: ['db'] },
      { id: 'work', jobs: [{ id: 'j1', bullets: { tags: ['api'] }, extra: ['Extra bullet.'] }, { id: 'j2', bullets: 'all' }] },
      { id: 'proj' },
      { id: 'edu', heading: 'Studies' },
    ],
  });
  for (const part of [
    '# Casey Example', '**Backend Developer**', '- E: [casey@example.com](mailto:casey@example.com)',
    'First para.\n\nSecond para.', 'Alpha · Beta', '- **Data:** SQL', '### Engineer | 2020 to now', '*One Ltd*',
    '**APIs**', '- Built **the API**.', '- Extra bullet.', '### Developer | 2015 to 2020', '- Wrote services.',
    '### Demo', 'A demo.', '- Features', '  - One', '- **Stack:** Java, SQL', '- **My role:** Sole developer',
    '- **Repository:** [github.com/example/demo](https://github.com/example/demo)', '## Studies', 'BSc, 2015.',
  ]) assert.ok(md.includes(part), `missing in the built CV: ${JSON.stringify(part)}\n--- CV ---\n${md}`);
  for (const absent of ['Default summary.', 'Ran the jobs.', '**Backend:**', '**Ops**']) {
    assert.ok(!md.includes(absent), `must not be in the built CV: ${JSON.stringify(absent)}`);
  }
});

test('contacts: a new text replaces, null drops', () => {
  const md = build({ title: 'Literal Title', contacts: { phone: null, city: 'Lisbon' }, sections: [{ id: 'edu' }] });
  assert.ok(md.includes('**Literal Title**'), 'a title that is not a titles id is used as literal text');
  assert.ok(md.includes('- Location: Lisbon'));
  assert.ok(!md.includes('+000 1'), 'a contact set to null must be dropped');
});

test('replace changes every text', () => {
  const md = build({ title: 'dev', replace: [{ from: 'Java', to: 'Kotlin' }], sections: [{ id: 'key' }, { id: 'proj' }] });
  assert.ok(md.includes('- **Backend:** Kotlin') && md.includes('Kotlin, SQL') && !md.includes('Java'), md);
});

test('merged jobs and { subhead } in a bullet list', () => {
  const md = build({
    title: 'dev',
    sections: [{
      id: 'work',
      jobs: [{
        id: 'j1', title: 'Engineer and Developer', dates: '2015 to now', bullets: [{ subhead: 'Recent' }, 'x', { subhead: 'Earlier' }, 'j2:z'],
      }],
    }],
  });
  assert.match(md, /### Engineer and Developer \| 2015 to now[\s\S]*\*\*Recent\*\*[\s\S]*- Built \*\*the API\*\*\.[\s\S]*\*\*Earlier\*\*[\s\S]*- Wrote services\./);
  assert.ok(!md.includes('**APIs**'), 'explicit bullet lists take subheads only from { subhead }');
});

test('groups: false hides the group subheads', () => {
  const md = build({ title: 'dev', sections: [{ id: 'work', jobs: [{ id: 'j1', groups: false }] }] });
  assert.ok(md.includes('- Ran the jobs.') && !md.includes('**APIs**') && !md.includes('**Ops**'), md);
});

test('markdownUnits skips front matter and markup', () => {
  const units = markdownUnits('---\noutput: x\n---\n# Head\n\nLine one\nline two.\n\n- **Bold** [link](https://e.x)\n');
  assert.deepEqual(units, ['Head', 'Line one line two.', 'Bold link']);
});

// Wording rules of the seed workspace. Every rule needs a case here: a text the rule must stop and an honest text
// it must let through. A new rule in the template without a case fails the test.
const RULE_CASES = {
  '\\bGo(lang)?\\b(?! to)': {
    claim: 'I built payment services in Go.',
    honest: 'I have not worked with Go, but I learn new languages fast. Happy to go to the office.',
  },
  '\\bKubernetes\\b': {
    claim: 'I run Kubernetes clusters in production.',
    honest: 'Docker; working knowledge of Kubernetes.',
  },
};

function lintText(ws, text, name) {
  const file = path.join(ws, `${name}.md`);
  fs.writeFileSync(file, text);
  return runScript('cv.js', ['--lint', file, '--root', ws]);
}

test('each wording rule of the template stops a claim and lets an honest text through', () => {
  const ws = seedWorkspace('rules');
  const { rules } = YAML.parse(fs.readFileSync(path.join(ws, 'MyProfile/cv/cv_rules.yaml'), 'utf8'));
  for (const rule of rules) {
    const c = RULE_CASES[rule.pattern];
    assert.ok(c, `no test case for the template rule ${JSON.stringify(rule.pattern)}: add one to RULE_CASES in ${__filename}`);
    const bad = lintText(ws, c.claim, 'claim');
    assert.equal(bad.code, 1, `rule ${rule.pattern} must fail on: ${c.claim}\noutput:\n${bad.all}`);
    assert.ok(bad.all.includes(rule.message), `the failure must print the rule message "${rule.message}"`);
    const ok = lintText(ws, c.honest, 'honest');
    assert.equal(ok.code, 0, `rule ${rule.pattern} must pass: ${c.honest}\noutput:\n${ok.all}`);
  }
});

test('a claim next to an honest negation in the same paragraph still fails', () => {
  const ws = seedWorkspace('rules2');
  const r = lintText(ws, 'I have not worked with Go. I wrote the gateway in Go.', 'mixed');
  assert.equal(r.code, 1, `the second sentence claims Go:\n${r.all}`);
});

test('--lint without wording rules prints a warning', () => {
  const dir = tempDir('norules');
  fs.writeFileSync(path.join(dir, 'a.md'), 'Text.\n');
  const r = runScript('cv.js', ['--lint', path.join(dir, 'a.md'), '--root', dir]);
  assert.match(r.err, /WARNING: no wording rules .*nothing was checked/, `the lint must not pass silently:\n${r.all}`);
});

function buildProfile(ws, profile) {
  const file = path.join(ws, 'p.yaml');
  fs.writeFileSync(file, YAML.stringify(profile));
  return runScript('cv.js', [file, '--no-docx'], { cwd: ws });
}

test('a bad selector or an unknown id fails with a clear message', () => {
  const ws = seedWorkspace('errors');
  const cases = [
    [{ title: 'backend', sections: [{ id: 'nope' }] }, /section "nope" not found in the master/],
    [{ title: 'backend', sections: [{ id: 'work', jobs: [{ id: 'nope' }] }] }, /job "nope" not found/],
    [{ title: 'backend', sections: [{ id: 'work', jobs: [{ id: 'example-payments', bullets: ['nope'] }] }] }, /bullet of job "example-payments" "nope" not found/],
    [{ title: 'backend', sections: [{ id: 'key-skills', groups: 'some' }] }, /bad selector for group of "key-skills": "some"/],
    [{ title: 'backend', sections: [{ id: 'summary', variant: 'nope' }] }, /summary variant "nope" not found/],
    [{ title: 'backend', sections: [{ id: 'summary' }], replace: [{ from: 'Nowhere text', to: 'x' }] }, /replace: "Nowhere text" not found/],
    [{ sections: [{ id: 'summary' }] }, /profile has no title/],
  ];
  for (const [profile, message] of cases) {
    const r = buildProfile(ws, profile);
    assert.equal(r.code, 1, `must fail: ${JSON.stringify(profile)}\noutput:\n${r.all}`);
    assert.match(r.err, message);
  }
});
