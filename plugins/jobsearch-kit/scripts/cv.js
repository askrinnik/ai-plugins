// Builds a CV from the master content file and a profile.
//
// Usage: node scripts/cv.js <profile.yaml> [--no-docx] [--root <workspace>]
//        node scripts/cv.js --lint <file.md> [<file.md> ...] [--root <workspace>]
//
// --lint checks any Markdown file (a cover letter, a form answer, a built CV) against cv_rules.yaml and builds
// nothing. Front matter is skipped. A text unit is a heading, a list item or a paragraph (lines up to a blank line).
// The output is the same as for a failed CV build; the exit code is 1 on a violation.
//
// The workspace root is found as described in workspace.js (by default: the nearest folder upwards from the
// current directory that holds MyProfile/cv/cv_master.yaml). The paths below are relative to it.
//
// Files:
//   MyProfile/cv/cv_master.yaml   all CV content, the single source (header, summaries, skills, jobs, projects, ...)
//   MyProfile/cv/cv_rules.yaml    wording rules taken from MyProfile/candidate_facts.md; the build fails on a violation
//   <folder>/cv_profile.yaml      what one CV contains: title, summary, sections, order, bullets, replacements
//   MyProfile/cv/profile_full.yaml  the profile of the full CV
//
// Output, next to the profile: <output>.md (the resolved text, compare it with git diff) and <output>.docx.
// "output" in the profile is a file name without extension; the default is "cv".
//
// Master format (YAML):
//   header: { name, photo, contacts: [ { id, label, text, url? } ] }
//   titles: { <id>: "..." }                       job titles for the header
//   sections:                                     in the default order
//     - id, heading, kind, ...                    kind is one of:
//       text:     variants: { <id>: "paragraph" or [paragraphs] }
//       list:     items: [ { id, text } ]         plain bullets (or one inline paragraph, see profile "inline")
//       groups:   groups: [ { id, label, text } ] bullets with a bold label
//       jobs:     jobs: [ { id, title, dates, company, bullets: [ { id, tags?, group?, text } ] } ]
//       projects: projects: [ { id, title, paras: [..], features: [ { text, items: [..] } ], stack: [..], role,
//                 link?: { text, url } } ]
//       paras:    paras: [ "..." ]
// Profile format (YAML):
//   master: path to the master file (optional, relative to the profile; default MyProfile/cv/cv_master.yaml)
//   output: file name without extension
//   title: <titles id> or literal text
//   contacts: { <contact id>: "new text" or null to drop }   (optional)
//   sections:                                     in the order they appear in the CV
//     - id: <master section id>
//       heading: "..."                            (optional override)
//       variant: <id> | text: "..."               kind text
//       items: all | [ids]; inline: true          kind list
//       groups: all | [ids]                       kind groups
//       jobs: [ { id, title?, dates?, company?, bullets: all | [ids] | { tags: [..] }, extra: [ "text" ],
//                 groups: false } ]               kind jobs; "groups: false" hides the group subheads.
//                                                 A bullet list may also hold "<job id>:<bullet id>" (merge
//                                                 several master jobs into one entry) and { subhead: "..." }.
//       projects: all | [ids]                     kind projects
//   replace: [ { from: "...", to: "..." } ]       applied to every text; each "from" must be found
const fs = require('fs');
const path = require('path');
const { requireDep, takeRootArg, findRoot, MASTER_REL } = require('./workspace');
const YAML = requireDep('yaml');
const { render } = require('./build-cv');

let ROOT = findRoot();
const rulesPath = () => path.join(ROOT, 'MyProfile', 'cv', 'cv_rules.yaml');

const fail = (msg) => { console.error('ERROR: ' + msg); process.exit(1); };
const load = (file) => YAML.parse(fs.readFileSync(file, 'utf8'));
const byId = (list, id, what) => list.find((x) => x.id === id) || fail(`${what} "${id}" not found in the master`);
const pick = (list, sel, what) => {
  if (sel === undefined || sel === 'all') return list;
  if (Array.isArray(sel)) return sel.map((id) => byId(list, id, what));
  if (sel.tags) return list.filter((x) => (x.tags || []).some((t) => sel.tags.includes(t)));
  return fail(`bad selector for ${what}: ${JSON.stringify(sel)}`);
};
const asArray = (v) => (Array.isArray(v) ? v : [v]);

function resolveSection(sec, ps, master) {
  const blocks = [];
  switch (sec.kind) {
    case 'text': {
      const text = ps.text !== undefined ? ps.text : (sec.variants[ps.variant || 'default']
        || fail(`summary variant "${ps.variant}" not found in section "${sec.id}"`));
      asArray(text).forEach((t) => blocks.push({ type: 'para', text: t.trim() }));
      break;
    }
    case 'list': {
      const items = pick(sec.items, ps.items, `item of "${sec.id}"`);
      if (ps.inline) blocks.push({ type: 'para', text: items.map((i) => i.text).join(' · ') });
      else items.forEach((i) => blocks.push({ type: 'bullet', text: i.text }));
      break;
    }
    case 'groups':
      pick(sec.groups, ps.groups, `group of "${sec.id}"`)
        .forEach((g) => blocks.push({ type: 'labeled', label: g.label, text: g.text }));
      break;
    case 'jobs': {
      const jobs = ps.jobs ? ps.jobs : sec.jobs.map((j) => ({ id: j.id }));
      for (const pj of jobs) {
        const job = byId(sec.jobs, pj.id, 'job');
        blocks.push({ type: 'job', title: pj.title || job.title, dates: pj.dates || job.dates, company: pj.company || job.company });
        // A bullet list may mix "<bullet id>", "<job id>:<bullet id>" (to merge jobs) and { subhead: "..." }.
        const bullets = Array.isArray(pj.bullets)
          ? pj.bullets.map((ref) => {
            if (typeof ref === 'object') return { group: ref.subhead, subheadOnly: true };
            const [jid, bid] = ref.includes(':') ? ref.split(':') : [job.id, ref];
            return { ...byId(byId(sec.jobs, jid, 'job').bullets, bid, `bullet of job "${jid}"`), group: undefined };
          })
          : pick(job.bullets, pj.bullets, `bullet of job "${job.id}"`).map((b) => ({ ...b }));
        (pj.extra || []).forEach((text) => bullets.push({ text }));
        let group;
        for (const b of bullets) {
          if (pj.groups !== false && b.group && b.group !== group) {
            group = b.group;
            blocks.push({ type: 'subhead', text: group });
          }
          if (!b.subheadOnly) blocks.push({ type: 'bullet', text: b.text });
        }
      }
      break;
    }
    case 'projects':
      for (const p of pick(sec.projects, ps.projects, 'project')) {
        blocks.push({ type: 'project', title: p.title });
        (p.paras || []).forEach((t) => blocks.push({ type: 'para', text: t }));
        for (const f of p.features || []) {
          blocks.push({ type: 'bullet', text: f.text });
          (f.items || []).forEach((t) => blocks.push({ type: 'bullet2', text: t }));
        }
        if (p.stack) blocks.push({ type: 'labeled', label: 'Stack', text: p.stack.join(', ') });
        if (p.role) blocks.push({ type: 'labeled', label: 'My role', text: p.role });
        if (p.link) blocks.push({ type: 'labeled', label: 'Repository', text: p.link.text, url: p.link.url });
      }
      break;
    case 'paras':
      (sec.paras || []).forEach((t) => blocks.push({ type: 'para', text: t }));
      break;
    default:
      fail(`unknown kind "${sec.kind}" in section "${sec.id}"`);
  }
  return { heading: ps.heading || sec.heading, blocks };
}

function resolve(master, profile) {
  const contacts = master.header.contacts
    .filter((c) => !(profile.contacts && profile.contacts[c.id] === null))
    .map((c) => ({
      label: c.label,
      text: (profile.contacts && profile.contacts[c.id]) || c.text,
      ...(c.url ? { url: c.url } : {}),
    }));
  const title = (master.titles && master.titles[profile.title]) || profile.title || fail('profile has no title');
  const sections = profile.sections.map((ps) => resolveSection(byId(master.sections, ps.id, 'section'), ps, master));
  const content = { header: { name: master.header.name, title, photo: master.header.photo, contacts }, sections };

  // Text replacements: every "from" must be found at least once.
  for (const r of profile.replace || []) {
    let n = 0;
    const swap = (t) => (t.includes(r.from) ? (n += 1, t.split(r.from).join(r.to)) : t);
    content.header.title = swap(content.header.title);
    content.header.contacts.forEach((c) => { c.text = swap(c.text); });
    for (const s of content.sections) {
      s.heading = swap(s.heading);
      for (const b of s.blocks) for (const k of ['text', 'title', 'label', 'company']) if (b[k]) b[k] = swap(b[k]);
    }
    if (!n) fail(`replace: "${r.from}" not found`);
  }
  return content;
}

// Text units for the wording rules: header lines and every block.
function units(content) {
  const out = [content.header.title, ...content.header.contacts.map((c) => `${c.label}: ${c.text}`)];
  for (const s of content.sections) {
    for (const b of s.blocks) {
      out.push([b.label, b.title, b.dates, b.company, b.text].filter(Boolean).join(' '));
    }
  }
  return out;
}

// Text units of a Markdown file: headings, list items and paragraphs, without front matter and markup.
function markdownUnits(text) {
  const lines = text.replace(/\r\n/g, '\n').replace(/^---\n[\s\S]*?\n---\n/, '').split('\n');
  const out = [];
  let cur = null;
  const flush = () => { if (cur) out.push(cur); cur = null; };
  for (const line of lines) {
    const t = line.trim();
    if (!t) { flush(); continue; }
    if (/^(#{1,6}\s|[-*+]\s|\d+[.)]\s|>)/.test(t)) { flush(); cur = t; continue; }
    cur = cur ? `${cur} ${t}` : t;
  }
  flush();
  return out.map((u) => u
    .replace(/^(#{1,6}\s+|[-*+]\s+|\d+[.)]\s+|>\s*)/, '')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\*\*|__|`/g, ''));
}

// Checks text units against the wording rules. "allow" matches are cut out of a unit before "pattern" is tested.
function lintUnits(list) {
  const RULES = rulesPath();
  if (!fs.existsSync(RULES)) {
    console.error(`WARNING: no wording rules at ${RULES}; nothing was checked. Pass --root <workspace>.`);
    return [];
  }
  const rules = load(RULES).rules || [];
  const problems = [];
  for (const u of list) {
    for (const r of rules) {
      const rest = (r.allow ? asArray(r.allow) : []).reduce((t, a) => t.replace(new RegExp(a, 'gi'), ' '), u);
      if (!new RegExp(r.pattern, r.flags || '').test(rest)) continue;
      if (r.unless && new RegExp(r.unless, r.unless_flags || r.flags || '').test(u)) continue;
      problems.push(`${r.message}\n    in: ${u.length > 160 ? u.slice(0, 157) + '...' : u}`);
    }
  }
  return problems;
}

const lint = (content) => lintUnits(units(content));

function report(problems) {
  if (!problems.length) return;
  console.error(`Wording rules failed (${rulesPath()}):`);
  problems.forEach((p) => console.error('  - ' + p));
  process.exit(1);
}

const plain = (t) => t;
function toMarkdown(content) {
  const h = content.header;
  const lines = [`# ${h.name}`, '', `**${h.title}**`, ''];
  h.contacts.forEach((c) => lines.push(`- ${c.label}: ${c.url ? `[${c.text}](${c.url})` : c.text}`));
  for (const s of content.sections) {
    lines.push('', `## ${s.heading}`, '');
    for (const b of s.blocks) {
      switch (b.type) {
        case 'para': lines.push(plain(b.text), ''); break;
        case 'bullet': lines.push(`- ${plain(b.text)}`); break;
        case 'bullet2': lines.push(`  - ${plain(b.text)}`); break;
        case 'labeled': lines.push(`- **${b.label}:** ${b.url ? `[${b.text}](${b.url})` : plain(b.text)}`); break;
        case 'job': lines.push('', `### ${b.title} | ${b.dates}`, '', `*${b.company}*`, ''); break;
        case 'subhead': lines.push('', `**${b.text}**`, ''); break;
        case 'project': lines.push('', `### ${b.title}`, ''); break;
        default: throw new Error(`Unknown block type: ${b.type}`);
      }
    }
  }
  return lines.join('\n').replace(/\n{3,}/g, '\n\n').trim() + '\n';
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const rootArg = takeRootArg(args);
  // Without --root, look for the workspace upwards from the current directory, then from each input file.
  const inputDirs = args.filter((a) => !a.startsWith('--')).map((f) => path.dirname(path.resolve(f)));
  ROOT = findRoot(rootArg, [process.cwd(), ...inputDirs]);
  if (args.includes('--lint')) {
    const files = args.filter((a) => !a.startsWith('--'));
    if (!files.length) fail('Usage: node scripts/cv.js --lint <file.md> [<file.md> ...] [--root <workspace>]');
    report(files.flatMap((f) => lintUnits(markdownUnits(fs.readFileSync(f, 'utf8')))
      .map((p) => p.replace('\n    in: ', `\n    file: ${f}\n    in: `))));
    files.forEach((f) => console.log('lint ok', f));
    process.exit(0);
  }
  const profilePath = args.find((a) => !a.startsWith('--'));
  if (!profilePath) fail('Usage: node scripts/cv.js <profile.yaml> [--no-docx] [--root <workspace>]');
  const profile = load(profilePath);
  const dir = path.dirname(path.resolve(profilePath));
  const masterPath = profile.master ? path.resolve(dir, profile.master) : path.join(ROOT, MASTER_REL);
  const content = resolve(load(masterPath), profile);

  report(lint(content));

  const base = path.join(dir, profile.output || 'cv');
  fs.writeFileSync(base + '.md', toMarkdown(content));
  console.log('written', base + '.md');
  if (!args.includes('--no-docx')) {
    render(content, base + '.docx', ROOT).then((size) => console.log('written', base + '.docx', size));
  }
}

module.exports = { resolve, lint, lintUnits, markdownUnits, toMarkdown };
