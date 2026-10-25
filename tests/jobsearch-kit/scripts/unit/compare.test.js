// compare-cv.js: the comparison of a base CV with a built CV.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { SCRIPTS, seedWorkspace, tempDir, runScript } = require('./helpers');
const { compare, numbers } = require(path.join(SCRIPTS, 'compare-cv.js'));

const BASE = [
  'Riley Example',
  'Backend Developer',
  'Built the shipment tracking API with Python, FastAPI and PostgreSQL.',
  'The API serves about 300,000 requests per day.',
  'Moved the nightly reports to Celery tasks; report time fell from 2 hours to 15 minutes.',
  'Wrote integration tests for the content services.',
  'Fluent English',
  'Docker, Docker Compose',
  'Redis',
];

test('a CV with the same text, regrouped and in Markdown, has no differences', () => {
  const cv = [
    '# Riley Example', '', '**Backend Developer**', '',
    '- Built the shipment tracking API with **Python**, FastAPI and PostgreSQL.',
    '- The API serves about 300000 requests per day.',
    '- Moved the nightly reports to Celery tasks; report time fell from 2 hours to 15 minutes.',
    '- Wrote integration tests for the content services.',
    '- Fluent English',
    '- Containers and cache: Docker, Docker Compose; Redis',
  ];
  const r = compare(BASE, cv);
  assert.deepEqual(r.summary, {
    baseUnits: 9, kept: 9, changed: 0, lost: 0, added: 0, numbersOnlyInBase: 0, numbersOnlyInCv: 0,
  }, JSON.stringify(r, null, 2));
});

test('a lost line, a changed line, an added line and a changed number are reported', () => {
  const cv = [
    'Riley Example', 'Backend Developer',
    'Built the shipment tracking API with Python, FastAPI and PostgreSQL.',
    'The API serves about 500,000 requests per day.',
    'Moved the nightly reports to Celery tasks; report time fell from 2 hours to 15 minutes.',
    'English (C1)',
    'Docker, Docker Compose', 'Redis',
    'Led the migration of all services to Kubernetes.',
  ];
  const r = compare(BASE, cv);
  assert.deepEqual(r.lost.map((x) => x.base), ['Wrote integration tests for the content services.']);
  assert.deepEqual(r.changed.map((x) => [x.base, x.cv]), [['Fluent English', 'English (C1)']]);
  assert.deepEqual(r.added.map((x) => x.cv), ['Led the migration of all services to Kubernetes.']);
  assert.deepEqual(r.numbersOnlyInBase, ['300000']);
  assert.deepEqual(r.numbersOnlyInCv, ['500000']);
});

test('numbers keep their unit and skip the digits of words', () => {
  assert.deepEqual(numbers('B2, 40% of 2,000,000 requests in 2019; 5+ years, 1.5k users, A2, 10x, 300 ms'),
    ['40%', '2000000', '2019', '5+', '1.5k', '300']);
});

test('compare-cv.js reads a .docx: the full CV of the seed matches its own .md', () => {
  const ws = seedWorkspace('compare');
  const build = runScript('cv.js', ['MyProfile/cv/profile_full.yaml'], { cwd: ws });
  assert.equal(build.code, 0, build.all);
  const md = fs.readdirSync(path.join(ws, 'MyProfile', 'cv')).find((f) => /_full\.md$/.test(f));
  const docx = md.replace(/\.md$/, '.docx');
  const r = runScript('compare-cv.js', [`MyProfile/cv/${docx}`, `MyProfile/cv/${md}`, '--json'], { cwd: ws });
  assert.equal(r.code, 0, r.all);
  const s = JSON.parse(r.out).summary;
  assert.ok(s.baseUnits > 20, `too few paragraphs read from the .docx: ${s.baseUnits}`);
  assert.equal(s.lost + s.changed + s.added + s.numbersOnlyInBase + s.numbersOnlyInCv, 0, r.out);
});

test('compare-cv.js prints a report, refuses a .pdf and reports a missing file', () => {
  const dir = tempDir('compare');
  fs.writeFileSync(path.join(dir, 'base.txt'), BASE.join('\n'));
  fs.writeFileSync(path.join(dir, 'cv.md'), BASE.slice(0, -1).join('\n'));
  const r = runScript('compare-cv.js', ['base.txt', 'cv.md'], { cwd: dir });
  assert.equal(r.code, 0, r.all);
  assert.match(r.out, /kept 8, changed 0, lost 1/);
  assert.match(r.out, /## Lost[\s\S]*\| Redis \|/);
  const pdf = runScript('compare-cv.js', ['base.pdf', 'cv.md'], { cwd: dir });
  fs.writeFileSync(path.join(dir, 'base.pdf'), '');
  const pdf2 = runScript('compare-cv.js', ['base.pdf', 'cv.md'], { cwd: dir });
  assert.match(pdf.err, /file not found/);
  assert.match(pdf2.err, /save the text of the PDF/);
});
