// Renders a CV (.docx) from a content object. Used by scripts/cv.js (master YAML + profile), and directly:
// Usage: node scripts/build-cv.js <content.json> <output.docx> [--root <workspace>]
//
// Content format (older application folders keep their cv_content.json in this format):
// {
//   "header": { "name": "...", "title": "...", "photo": "MyProfile/photo.jpg",
//               "contacts": [ { "label": "E", "text": "...", "url": "mailto:..." } ] },
//   "sections": [ { "heading": "...", "blocks": [ <block>, ... ] } ]
// }
// Block types:
//   { "type": "para", "text": "..." }
//   { "type": "bullet", "text": "..." }
//   { "type": "bullet2", "text": "..." }                       second-level bullet (dash)
//   { "type": "labeled", "label": "Backend", "text": "..." }   bullet with a bold label
//                                                              ("url" makes the text a hyperlink)
//   { "type": "job", "title": "...", "dates": "...", "company": "..." }
//   { "type": "subhead", "text": "..." }                       small accent heading inside a job
//   { "type": "project", "title": "..." }                      project title
// In any "text", **double asterisks** mark bold fragments.
// Relative paths (photo) are resolved against the workspace root (see workspace.js).
// npm packages live outside the plugin and the workspace: see workspace.js and scripts/install-deps.ps1.
const fs = require('fs');
const path = require('path');
const { requireDep, takeRootArg, findRoot } = require('./workspace');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, WidthType,
  BorderStyle, ImageRun, ExternalHyperlink, AlignmentType, LevelFormat, VerticalAlign,
} = requireDep('docx');

const ACCENT = '2E5395';
const JOB_COLOR = '1F497D';
const NAME_COLOR = '7C9BAE';
const MUTED = '595959';
const HEAD_FONT = 'Century Gothic';
const BODY_FONT = 'Arial';
const CONTACT_FONT = 'Verdana';

const t = (text, opts = {}) => new TextRun({ text, font: BODY_FONT, size: 20, ...opts });

// Splits "**bold** text" into runs.
const rich = (text, opts = {}) => text.split(/(\*\*[^*]+\*\*)/).filter(Boolean).map((part) => (
  part.startsWith('**') ? t(part.slice(2, -2), { ...opts, bold: true }) : t(part, opts)));

const heading = (text) => new Paragraph({
  spacing: { before: 280, after: 120 },
  keepNext: true,
  border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: NAME_COLOR, space: 2 } },
  children: [new TextRun({ text, font: HEAD_FONT, size: 30, color: ACCENT })],
});

const blockRenderers = {
  para: (b) => [new Paragraph({
    spacing: { after: 80, line: 264 },
    alignment: AlignmentType.JUSTIFIED,
    children: rich(b.text),
  })],
  bullet: (b) => [new Paragraph({
    numbering: { reference: 'bullets', level: 0 },
    spacing: { after: 40, line: 252 },
    children: rich(b.text),
  })],
  bullet2: (b) => [new Paragraph({
    numbering: { reference: 'bullets', level: 1 },
    spacing: { after: 20, line: 252 },
    children: rich(b.text),
  })],
  labeled: (b) => [new Paragraph({
    numbering: { reference: 'bullets', level: 0 },
    spacing: { after: 40, line: 252 },
    children: [
      t(b.label + ': ', { bold: true }),
      ...(b.url
        ? [new ExternalHyperlink({ link: b.url, children: [t(b.text, { color: '0563C1', underline: {} })] })]
        : rich(b.text)),
    ],
  })],
  job: (b) => [
    new Paragraph({
      spacing: { before: 200, after: 20 },
      keepNext: true,
      children: [
        new TextRun({ text: b.title, font: HEAD_FONT, size: 23, bold: true, color: JOB_COLOR }),
        new TextRun({ text: '  |  ' + b.dates, font: HEAD_FONT, size: 20, color: MUTED }),
      ],
    }),
    new Paragraph({
      spacing: { after: 80 },
      keepNext: true,
      children: [t(b.company, { italics: true, color: MUTED })],
    }),
  ],
  subhead: (b) => [new Paragraph({
    spacing: { before: 100, after: 40 },
    keepNext: true,
    children: [t(b.text, { bold: true, color: ACCENT })],
  })],
  project: (b) => [new Paragraph({
    spacing: { before: 160, after: 40 },
    keepNext: true,
    children: [new TextRun({ text: b.title, font: HEAD_FONT, size: 22, bold: true, color: JOB_COLOR })],
  })],
};

const renderBlock = (b) => {
  const render = blockRenderers[b.type];
  if (!render) throw new Error(`Unknown block type: ${b.type}`);
  return render(b);
};

const noBorder = { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' };
const cellBorders = {
  top: noBorder, left: noBorder, right: noBorder,
  bottom: { style: BorderStyle.SINGLE, size: 4, color: NAME_COLOR },
};
const LEFT_W = 7206;
const RIGHT_W = 2700;

function renderHeader(h, root) {
  const contactRun = (text) => new TextRun({ text, font: CONTACT_FONT, size: 17 });
  const contacts = h.contacts.map((c) => new Paragraph({
    spacing: { before: 30 },
    children: [
      contactRun(c.label + ': '),
      c.url
        ? new ExternalHyperlink({
          link: c.url,
          children: [new TextRun({ text: c.text, font: CONTACT_FONT, size: 17, color: '0563C1', underline: {} })],
        })
        : contactRun(c.text),
    ],
  }));

  const photoCell = h.photo ? [new Paragraph({
    alignment: AlignmentType.RIGHT,
    children: [new ImageRun({
      type: path.extname(h.photo).toLowerCase() === '.png' ? 'png' : 'jpg',
      data: fs.readFileSync(path.resolve(root, h.photo)),
      transformation: { width: 140, height: 140 },
      altText: { title: 'Photo', description: h.name, name: 'photo' },
    })],
  })] : [new Paragraph({})];

  return new Table({
    width: { size: LEFT_W + RIGHT_W, type: WidthType.DXA },
    columnWidths: [LEFT_W, RIGHT_W],
    borders: {
      top: noBorder, bottom: noBorder, left: noBorder, right: noBorder,
      insideHorizontal: noBorder, insideVertical: noBorder,
    },
    rows: [new TableRow({
      children: [
        new TableCell({
          width: { size: LEFT_W, type: WidthType.DXA },
          borders: cellBorders,
          margins: { bottom: 160 },
          children: [
            new Paragraph({ children: [new TextRun({ text: h.name, font: HEAD_FONT, size: 36, color: NAME_COLOR })] }),
            new Paragraph({
              spacing: { after: 160 },
              children: [new TextRun({ text: h.title, font: HEAD_FONT, size: 26 })],
            }),
            ...contacts,
          ],
        }),
        new TableCell({
          width: { size: RIGHT_W, type: WidthType.DXA },
          borders: cellBorders,
          verticalAlignment: VerticalAlign.CENTER,
          children: photoCell,
        }),
      ],
    })],
  });
}

// Renders the content object to a .docx file. Returns a promise with the file size.
// root is the workspace root that relative paths (photo) are resolved against.
function render(content, outPath, root = findRoot()) {
  const body = [
    renderHeader(content.header, root),
    ...content.sections.flatMap((s) => [heading(s.heading), ...s.blocks.flatMap(renderBlock)]),
  ];

  const doc = new Document({
    creator: content.header.name,
    title: `${content.header.name} - ${content.header.title}`,
    styles: { default: { document: { run: { font: BODY_FONT, size: 20 } } } },
    numbering: {
      config: [{
        reference: 'bullets',
        levels: [{
          level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 360, hanging: 260 } } },
        }, {
          level: 1, format: LevelFormat.BULLET, text: '–', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 260 } } },
        }],
      }],
    },
    sections: [{
      properties: {
        page: {
          size: { width: 11906, height: 16838 }, // A4
          margin: { top: 900, right: 900, bottom: 900, left: 1100 },
        },
      },
      children: body,
    }],
  });

  return Packer.toBuffer(doc).then((buf) => {
    fs.writeFileSync(outPath, buf);
    return buf.length;
  });
}

module.exports = { render };

if (require.main === module) {
  const args = process.argv.slice(2);
  const root = findRoot(takeRootArg(args));
  const [contentPath, outPath] = args;
  if (!contentPath || !outPath) {
    console.error('Usage: node scripts/build-cv.js <content.json> <output.docx> [--root <workspace>]');
    process.exit(1);
  }
  render(JSON.parse(fs.readFileSync(contentPath, 'utf8')), outPath, root)
    .then((size) => console.log('written', outPath, size));
}
