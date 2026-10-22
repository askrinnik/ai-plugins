// build-cv.js (an older cv_content.json) and build-letter.js (a letter from Markdown).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { tempDir, runScript, docxParagraphs } = require('./helpers');

test('build-cv.js renders an older cv_content.json', async () => {
  const dir = tempDir('content');
  const content = {
    header: {
      name: 'Casey Example',
      title: 'Backend Developer',
      contacts: [{ label: 'E', text: 'casey@example.com', url: 'mailto:casey@example.com' }],
    },
    sections: [{
      heading: 'Work',
      blocks: [
        { type: 'job', title: 'Engineer', dates: '2020 to now', company: 'One Ltd' },
        { type: 'subhead', text: 'APIs' },
        { type: 'bullet', text: 'Built **the API**.' },
        { type: 'bullet2', text: 'Second level.' },
        { type: 'labeled', label: 'Stack', text: 'Java' },
        { type: 'project', title: 'Demo' },
        { type: 'para', text: 'A paragraph.' },
      ],
    }],
  };
  fs.writeFileSync(path.join(dir, 'cv_content.json'), JSON.stringify(content));
  const out = path.join(dir, 'cv.docx');
  const r = runScript('build-cv.js', [path.join(dir, 'cv_content.json'), out, '--root', dir]);
  assert.equal(r.code, 0, r.all);
  const texts = (await docxParagraphs(out)).map((p) => p.text);
  for (const t of ['Casey Example', 'Backend Developer', 'Work', 'APIs', 'Built the API.', 'Second level.', 'Demo', 'A paragraph.']) {
    assert.ok(texts.includes(t), `paragraph "${t}" missing in the .docx; paragraphs: ${JSON.stringify(texts)}`);
  }
});

test('build-cv.js without arguments prints the usage', () => {
  const r = runScript('build-cv.js', []);
  assert.equal(r.code, 1);
  assert.match(r.err, /Usage: node scripts\/build-cv\.js/);
});

const LETTER = [
  '---',
  'output: 2026_01_15_Cover_Letter_Casey_Example',
  'date: 15 January 2026',
  '---',
  'Dear hiring team,',
  '',
  'First paragraph with a **bold fragment** in it, written on one line.',
  '',
  'Second paragraph.',
  '',
  'Kind regards,',
  'Casey Example',
  '',
].join('\n');

test('build-letter.js: front matter, one paragraph per block, bold fragments, output name', async () => {
  const dir = tempDir('letter');
  const md = path.join(dir, 'cover-letter.md');
  fs.writeFileSync(md, LETTER.replace(/\n/g, '\r\n'));
  const r = runScript('build-letter.js', [md]);
  assert.equal(r.code, 0, r.all);
  const out = path.join(dir, '2026_01_15_Cover_Letter_Casey_Example.docx');
  assert.ok(fs.existsSync(out), `front matter "output" must name the file: expected ${out}; script output: ${r.all}`);
  assert.ok(!fs.existsSync(path.join(dir, 'cover-letter.docx')), 'the .md name must not be used when "output" is set');
  const paras = await docxParagraphs(out);
  assert.deepEqual(paras.map((p) => p.text), [
    '15 January 2026',
    'Dear hiring team,',
    'First paragraph with a bold fragment in it, written on one line.',
    'Second paragraph.',
    'Kind regards,Casey Example',
  ], 'the date from the front matter comes first, then one paragraph per Markdown block; front matter text is not printed');
  assert.deepEqual(paras[2].bold, ['bold fragment'], '**text** must become a bold run');
  assert.equal(paras[4].breaks, 1, 'lines inside one block stay separate lines (a line break, not a new paragraph)');
});

test('build-letter.js without front matter names the output after the .md file', () => {
  const dir = tempDir('letter2');
  const md = path.join(dir, 'letter.md');
  fs.writeFileSync(md, 'Hello.\n');
  const r = runScript('build-letter.js', [md]);
  assert.equal(r.code, 0, r.all);
  assert.ok(fs.existsSync(path.join(dir, 'letter.docx')), r.all);
});
