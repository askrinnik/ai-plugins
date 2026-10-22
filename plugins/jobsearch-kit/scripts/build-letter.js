// Builds a letter (.docx) from a Markdown file, for example a cover letter.
// Usage: node scripts/build-letter.js <letter.md>
//
// The Markdown file is the source: keep one line per paragraph, so the text can also be pasted into a web form.
// Optional front matter at the top:
//   ---
//   output: 2026_10_21_Cover_Letter_<Name>_<Company>   (file name without extension; default: the .md name)
//   date: 21 October 2026                              (printed above the greeting)
//   ---
// Paragraphs are separated by blank lines. Lines inside one block (for example the signature) stay on separate lines.
// **double asterisks** mark bold fragments. Output: <output>.docx next to the .md file.
// Make the PDF with scripts/export-pdf.ps1.
const fs = require('fs');
const path = require('path');
const { requireDep } = require('./workspace');
const { Document, Packer, Paragraph, TextRun } = requireDep('docx');

const FONT = 'Arial';
const SIZE = 22; // half-points: 11 pt

const mdPath = process.argv[2];
if (!mdPath) {
  console.error('Usage: node scripts/build-letter.js <letter.md>');
  process.exit(1);
}

let text = fs.readFileSync(mdPath, 'utf8').replace(/\r\n/g, '\n');
const meta = {};
const fm = text.match(/^---\n([\s\S]*?)\n---\n/);
if (fm) {
  fm[1].split('\n').forEach((line) => {
    const m = line.match(/^(\w+):\s*(.*)$/);
    if (m) meta[m[1]] = m[2].trim();
  });
  text = text.slice(fm[0].length);
}

const runs = (line) => line.split(/(\*\*[^*]+\*\*)/).filter(Boolean).map((part) => (
  part.startsWith('**')
    ? new TextRun({ text: part.slice(2, -2), font: FONT, size: SIZE, bold: true })
    : new TextRun({ text: part, font: FONT, size: SIZE })));

const blocks = text.split(/\n\s*\n/).map((b) => b.trim()).filter(Boolean);
if (meta.date) blocks.unshift(meta.date);

const paragraphs = blocks.map((block) => {
  const lines = block.split('\n');
  const children = lines.flatMap((line, i) => (i === 0 ? runs(line) : [new TextRun({ break: 1 }), ...runs(line)]));
  return new Paragraph({ spacing: { after: 200, line: 264 }, children });
});

const doc = new Document({
  styles: { default: { document: { run: { font: FONT, size: SIZE } } } },
  sections: [{
    properties: {
      page: {
        size: { width: 11906, height: 16838 }, // A4
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
      },
    },
    children: paragraphs,
  }],
});

const out = path.join(path.dirname(mdPath), (meta.output || path.basename(mdPath, '.md')) + '.docx');
Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(out, buf);
  console.log('written', out, buf.length);
});
