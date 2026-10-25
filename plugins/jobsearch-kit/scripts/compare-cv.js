// Compares the text of a base CV (the CV a workspace was set up from) with a built CV, so that nothing of the base
// CV is lost or changed without the user knowing it.
//
// Usage: node scripts/compare-cv.js <base> <cv.md> [--json]
//
// <base> is a .docx (the paragraphs of word/document.xml) or a text file (.txt, .md; for a .pdf or a LinkedIn
// export, save the extracted text to a text file first). <cv.md> is a built CV, for example
// MyProfile/cv/CV_<Name>_full.md.
//
// A unit is a non-empty line (a paragraph of a .docx). Markdown marks, links and list bullets are removed, and the
// text is compared without case. Each unit of the base gets one status:
//   kept     the unit is in the CV word for word (also inside a longer line, for example after a regrouping),
//            or the best matching CV line holds at least 80% of its words;
//   changed  the best matching CV line holds 50-80% of its words: the report shows both lines;
//   lost     no CV line holds half of its words.
// A unit of the CV is "added" if no base line holds half of its words and the whole base holds less than 80% of
// them (a line merged from several base lines, or a short group label before base text, is not added). Numbers
// (with %, +, k, m; not the digits of a word such as "B2") are compared separately: a number of one text that the
// other does not have is reported in any case.
//
// The script judges nothing: it reports. The exit code is 0 unless the input cannot be read.
const fs = require('fs');
const path = require('path');
const { requireDep } = require('./workspace');

const KEPT = 0.8;
const CHANGED = 0.5;
const STOP = new Set(('a an and are as at be by for from has have in into is it its of on or that the to was were '
  + 'with within we our i my me per').split(' '));

const fail = (msg) => { console.error('ERROR: ' + msg); process.exit(1); };

async function docxLines(file) {
  const JSZip = requireDep('jszip');
  const zip = await JSZip.loadAsync(fs.readFileSync(file));
  const xml = await zip.file('word/document.xml').async('string');
  const unescape = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'").replace(/&amp;/g, '&');
  return [...xml.matchAll(/<w:p[ >][\s\S]*?<\/w:p>/g)].map(([p]) => unescape(
    p.replace(/<w:tab\/>/g, ' ').replace(/<w:br\/>/g, '\n')
      .split(/(<w:t[^>]*>[^<]*<\/w:t>|\n)/).map((s) => {
        if (s === '\n') return '\n';
        const m = s.match(/^<w:t[^>]*>([^<]*)<\/w:t>$/);
        return m ? m[1] : '';
      }).join(''),
  )).flatMap((t) => t.split('\n'));
}

async function readLines(file) {
  if (!fs.existsSync(file)) fail(`file not found: ${file}`);
  if (/\.docx$/i.test(file)) return docxLines(file);
  if (/\.pdf$/i.test(file)) fail(`${file}: save the text of the PDF to a .txt file and compare that file`);
  return fs.readFileSync(file, 'utf8').replace(/^---\n[\s\S]*?\n---\n/, '').split(/\r?\n/);
}

// Plain text of a line: no Markdown marks, link targets or bullets; typographic quotes and dashes made plain.
function plain(line) {
  return line
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '')
    .replace(/\[([^\]]*)\]\(([^)]*)\)/g, '$1')
    .replace(/^\s*(#+|[-*•▪●]|\d+\.)\s+/, '')
    .replace(/[*_`]/g, '')
    .replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[–—]/g, '-')
    .replace(/\s+/g, ' ')
    .trim();
}

// Lower case, and "300,000" as "300000".
const norm = (text) => text.toLowerCase().replace(/(\d),(?=\d{3}(?!\d))/g, '$1');
const key = (text) => norm(text).replace(/[.;,:]+$/, '').trim();
const words = (text) => (norm(text).match(/[\p{L}\p{N}][\p{L}\p{N}.#+/-]*/gu) || [])
  .map((w) => w.replace(/[./-]+$/, ''))
  .filter((w) => w && !STOP.has(w));
const numbers = (text) => (text.match(/(?<![\p{L}\d.,])(?:\d[\d.,]*\d|\d)(?:\s*%|\+|[km](?!\p{L}))?(?![\p{L}\d])/giu) || [])
  .map((n) => n.replace(/\s+/g, '').replace(/,(?=\d{3}\b)/g, '').toLowerCase());

// The words of a line without a short leading label ("Containers and IaC: Docker" -> "Docker"): a CV may group
// the lines of the base under labels.
const bodyWords = (text) => {
  const m = text.match(/^([^:]{1,40}):\s+(.+)$/);
  return new Set(words(m && m[1].split(' ').length <= 4 ? m[2] : text));
};

function units(lines) {
  return lines.map(plain).filter((t) => words(t).length > 0)
    .map((text) => ({ text, key: key(text), words: new Set(words(text)), body: bodyWords(text) }));
}

// The share of the words of a that b holds.
function coverage(a, b) {
  if (a.words.size === 0) return 1;
  let n = 0;
  for (const w of a.words) if (b.words.has(w)) n += 1;
  return n / a.words.size;
}

function best(unit, others) {
  let top = { score: 0, unit: undefined };
  for (const o of others) {
    const score = coverage(unit, o);
    if (score > top.score) top = { score, unit: o };
  }
  return top;
}

function countAll(list) {
  const m = new Map();
  for (const x of list) m.set(x, (m.get(x) || 0) + 1);
  return m;
}

// Numbers of a that b has fewer times.
function missingNumbers(a, b) {
  const ca = countAll(a);
  const cb = countAll(b);
  return [...ca].filter(([n, k]) => (cb.get(n) || 0) < k).map(([n]) => n);
}

function compare(baseLines, cvLines) {
  const base = units(baseLines);
  const cv = units(cvLines);
  const cvText = cv.map((u) => u.key).join('\n');
  const result = { kept: [], changed: [], lost: [], added: [], numbersOnlyInBase: [], numbersOnlyInCv: [] };
  for (const u of base) {
    if (cvText.includes(u.key)) { result.kept.push({ base: u.text }); continue; }
    const top = best(u, cv);
    const item = { base: u.text, cv: top.unit && top.unit.text, score: Math.round(top.score * 100) };
    if (top.score >= KEPT) result.kept.push(item);
    else if (top.score >= CHANGED) result.changed.push(item);
    else result.lost.push(item);
  }
  const baseText = base.map((u) => u.key).join('\n');
  const baseAll = { words: new Set(base.flatMap((u) => [...u.words])) };
  for (const u of cv) {
    if (baseText.includes(u.key) || best(u, base).score >= CHANGED
      || coverage({ words: u.body }, baseAll) >= KEPT) continue;
    result.added.push({ cv: u.text });
  }
  const baseNumbers = base.flatMap((u) => numbers(u.text));
  const cvNumbers = cv.flatMap((u) => numbers(u.text));
  result.numbersOnlyInBase = missingNumbers(baseNumbers, cvNumbers);
  result.numbersOnlyInCv = missingNumbers(cvNumbers, baseNumbers);
  result.summary = {
    baseUnits: base.length, kept: result.kept.length, changed: result.changed.length, lost: result.lost.length,
    added: result.added.length, numbersOnlyInBase: result.numbersOnlyInBase.length,
    numbersOnlyInCv: result.numbersOnlyInCv.length,
  };
  return result;
}

function report(r, baseName, cvName) {
  const s = r.summary;
  const out = [
    `# CV comparison: ${baseName} -> ${cvName}`,
    '',
    `Base units: ${s.baseUnits}; kept ${s.kept}, changed ${s.changed}, lost ${s.lost}. Added in the CV: ${s.added}.`
      + ` Numbers only in the base: ${s.numbersOnlyInBase}; only in the CV: ${s.numbersOnlyInCv}.`,
  ];
  const cell = (t) => (t || '').replace(/\|/g, '\\|');
  if (r.lost.length) {
    out.push('', '## Lost: in the base CV, not in the CV', '', '| Base CV | Closest CV line | Words kept |', '|---|---|---|');
    r.lost.forEach((x) => out.push(`| ${cell(x.base)} | ${cell(x.cv)} | ${x.score}% |`));
  }
  if (r.changed.length) {
    out.push('', '## Changed', '', '| Base CV | CV | Words kept |', '|---|---|---|');
    r.changed.forEach((x) => out.push(`| ${cell(x.base)} | ${cell(x.cv)} | ${x.score}% |`));
  }
  if (r.added.length) {
    out.push('', '## Added: in the CV, not in the base CV', '');
    r.added.forEach((x) => out.push(`- ${x.cv}`));
  }
  if (r.numbersOnlyInBase.length || r.numbersOnlyInCv.length) {
    out.push('', '## Numbers', '');
    if (r.numbersOnlyInBase.length) out.push(`- Only in the base CV: ${r.numbersOnlyInBase.join(', ')}`);
    if (r.numbersOnlyInCv.length) out.push(`- Only in the CV: ${r.numbersOnlyInCv.join(', ')}`);
  }
  if (!s.changed && !s.lost && !s.added && !s.numbersOnlyInBase && !s.numbersOnlyInCv) {
    out.push('', 'No differences: every line of the base CV is in the CV.');
  }
  return out.join('\n');
}

async function main() {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const files = args.filter((a) => a !== '--json');
  if (files.length !== 2) fail('usage: node compare-cv.js <base.docx|base.txt> <cv.md> [--json]');
  const [baseFile, cvFile] = files;
  const r = compare(await readLines(baseFile), await readLines(cvFile));
  console.log(json ? JSON.stringify(r, null, 2) : report(r, path.basename(baseFile), path.basename(cvFile)));
}

if (require.main === module) main().catch((e) => fail(e.message));

module.exports = { compare, plain, numbers };
