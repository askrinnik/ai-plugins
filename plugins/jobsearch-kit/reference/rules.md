# Rules for all jobsearch-kit skills

The workspace `CLAUDE.md` may override any default here (see `workspace.md`, "Precedence").

## Core rules

- **Never invent experience.** The only sources are the facts (`MyProfile/candidate_facts.md`) and the master
  (`MyProfile/cv/cv_master.yaml`). Skills marked "working knowledge" stay that way. If something is not confirmed,
  ask the user, then record the answer with the `jobsearch-kit:update-cv-facts` skill.
- **A related fact is not the same fact.** If a requirement names an activity or a quality that the facts do not name
  (for example "mentoring", "high-load", "led"), and the facts only describe something related ("runs code reviews
  and onboarding", "about 2 million requests per day", "took part in"), do not rename the fact. Mark the requirement
  🟡 or ❓, name the related fact as evidence, and ask the user whether the stronger word is true. Use the stronger
  word only after the user confirms it.
- **Never submit applications, send messages or publish anything for the user.** Never click, tick or submit a form.
  The user does it.
- **LinkedIn and other sites are read only.** Never send connection requests or messages, never like or follow, and
  never change an account. If a page needs a sign-in, ask the user to sign in in the built-in browser and wait.
  Never type credentials.
- **Keep the master current.** If the user confirms or corrects a fact, run `jobsearch-kit:update-cv-facts` in the same
  session. Before you tailor a CV, check the master against the facts; if it misses confirmed facts, run
  `jobsearch-kit:update-cv-facts` first.
- **Never commit or push on your own.** Offer a commit at the end; commit only when the user says so. Push only on an
  explicit request.
- **Do not change archived files** that the workspace `CLAUDE.md` names.
- If Word locks a `.docx`, ask the user to close it. Do not close or kill a Word window that the user opened.

## Documents

Every document has a text source and is built by a script. Never edit a built `.docx` or PDF by hand.

| Document | Source | Build |
|---|---|---|
| Full CV | master + `MyProfile/cv/profile_full.yaml` | `cv.js MyProfile/cv/profile_full.yaml` |
| Tailored CV | master + `<application folder>/cv_profile.yaml` | `cv.js <folder>/cv_profile.yaml` |
| Cover letter | `<application folder>/cover-letter.md` | `build-letter.js`, then `export-pdf.ps1` |
| PDF for submission | the `.docx` | `export-pdf.ps1 -Docx <file.docx>` |

`scripts.md` gives the full commands.

- The CV build checks `MyProfile/cv/cv_rules.yaml` and stops on a violation. Fix the text. Change the rules only
  when the facts changed; never weaken a rule to pass the build.
- Check other Markdown text (cover letters, free-text form answers) with `cv.js --lint <file.md>`.
- Always check the layout visually before you report a document as done: render it with `render-preview.ps1` and
  read the page images.

## Cover letters

Defaults; the workspace "Cover letter preferences" add to them.

- Use only confirmed facts. Name the main gaps honestly ("I have not worked with X yet") and show the nearest real
  experience.
- Write one line per paragraph, without hard wraps, so that the text can be pasted into a web form.
- Keep the body to 250–350 words and the letter to one page.

## Writing style

Defaults, based on the writing rules of ASD-STE100 Simplified Technical English (not its dictionary). Apply them to
text in any language.

For every file:

- Start with the conclusion or answer. Then add the details.
- Give each paragraph one topic.
- Do not cut important conditions or caveats to make the text shorter.

By document type:

- **Spoken interview answers** ("Tell me about yourself", STAR stories, answers to likely questions in
  `interview-prep.md`): no more than 20 words in a sentence; active voice with "I" as the subject for the user's own
  actions; no more than three nouns in a row; keep the vacancy's keywords and technology names.
- **Checklists and procedures:** one action per item, in the imperative.
- **Notes** (company research, vacancy notes, fit analyses, call summaries, work log): one fact per sentence, about
  25 words at most. Give the source and its date for each fact. Keep facts and conclusions in separate sentences.
- **CVs and cover letters:** use the active voice and avoid noun clusters. Keep the vocabulary rich: these documents
  must sell.

Do not rewrite older documents only for style. Apply the rules to new text and to text that you change anyway.

## Diagrams and HTML pages

- If a structure, flow or timeline is easier to see than to read, add a Mermaid diagram (` ```mermaid `) to the
  Markdown note. Use it for company and legal entity structure, team and reporting lines, system design flows and
  interview stages or timelines.
- Keep a diagram to about 12 nodes; split a bigger one. Put a short text summary next to it; the text must stay
  correct without the diagram.
- Never put diagrams into CVs or cover letters.
- For a one-off overview that the user reads on screen (for example a cheat sheet before a call), make one
  self-contained `.html` file in the related folder: inline CSS and SVG, no external scripts, fonts or CDNs. Use the
  same facts as the Markdown notes and link to them. Show it with `SendUserFile`.
