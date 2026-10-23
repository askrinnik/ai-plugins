---
name: init-workspace
description: Set up a new job search workspace from zero with the user's own data - folder, settings, facts and master CV drafted from a base CV (.docx, .pdf, text or LinkedIn export), form answers, environment check and the first CV build. Use when the user starts with jobsearch-kit, asks to create or set up a workspace, or has no MyProfile/ folder yet.
---

# Set up a job search workspace

Before the first step, read `${CLAUDE_SKILL_DIR}/../../reference/workspace.md` (workspace layout, settings and
precedence) and `${CLAUDE_SKILL_DIR}/../../reference/rules.md` (core rules, documents, style).

The skeleton of a workspace is `${CLAUDE_SKILL_DIR}/../../templates/workspace/`: the files and formats with header
comments and placeholders (`<...>`), without any person's data.

**Never invent a fact. Never mark a fact as confirmed that the user did not confirm.** A statement taken from the
base CV is marked "from the CV, <date>" until the user confirms it; then it becomes "confirmed <date>".

```mermaid
flowchart LR
  F[1 Folder] --> S[2 Settings]
  S --> I[3 Import base CV]
  I --> C[4 Confirm facts]
  C --> A[5 Form answers]
  A --> P[6 Photo]
  P --> E[7 Environment]
  E --> B[8 First build]
  B --> N[9 Next step]
```

Summary: create the folder from the skeleton, record the settings, draft the facts and the master CV from the base
CV, let the user confirm every fact, fill the form answers, check the tools, build the full CV, and point to
`analyze-vacancy`.

Ask the questions of one step together in one message. Wait for the answers before you write the files of that step.
If the user gives all answers up front, do not ask again.

## 1. Folder

1. Ask where the workspace goes. If the user already works in an empty folder, offer that folder.
2. If the folder exists and is not empty, list what is in it and ask whether to continue. Never overwrite a file
   without a yes.
3. If the folder holds `tools/` or `.claude/skills/` with older copies of the job search skills, tell the user that
   the plugin replaces them, and offer to delete them. Delete only after a yes.
4. Copy the skeleton into the folder: every file and folder of `templates/workspace/`, including `.gitignore`. Keep
   files that exist (for example a `MyProfile/candidate_facts.md` of an older workspace) and tell the user which.
5. Run every later command from the workspace root.

## 2. Settings

1. Ask for the workspace settings of `workspace.md` ("Workspace settings"): conversation language, notes language,
   documents language, recruiter messages, cover letter preferences (for example: no start date, no referrer, no
   recruiter name), writing style, archived files. Offer the defaults.
2. Write the answers into the "Workspace settings" section of `CLAUDE.md`. Replace every placeholder.

## 3. Import the base CV

1. Ask for the base CV: a `.docx`, a `.pdf`, plain text, or a LinkedIn profile export (PDF or the `Profile.csv` and
   `Positions.csv` files of the data export).
2. Extract the text:
   - `.docx`: read `word/document.xml` from the zip and strip the tags (`Expand-Archive` in pwsh; Windows PowerShell
     5.1 refuses the `.docx` extension, so copy the file to `.zip` first).
   - `.pdf`: read the file with the Read tool. If that fails, extract the text with a PDF text tool.
   - Text or CSV: read it as it is.
3. Draft `MyProfile/candidate_facts.md` from the text, in the language the user chooses for it:
   - contacts and status (name, e-mail, phone, location, links);
   - experience (per job: period, title, company, city, stack, responsibilities and results);
   - key metrics (only numbers that the CV states);
   - skills by level (the level stays "not confirmed" until step 4).
   Mark every statement "from the CV, <today>". If the CV has nothing for a section, delete the placeholder line of
   that section; do not write a bullet such as "No projects".
4. Draft `MyProfile/cv/cv_master.yaml` in the documents language (format at the top of
   `${CLAUDE_SKILL_DIR}/../../scripts/cv.js`): `header` (name, contacts with `url` for links), `titles`, a summary
   with variants, a skills `list`, skill `groups`, `jobs` with tagged bullets (`tags` by topic, for example `api`,
   `data`, `lead`), `projects`, education. Keep the verbs and numbers of the base CV. Do not add skills or results
   that the base CV does not state.
5. In `MyProfile/cv/profile_full.yaml`, set `output: CV_<Name>_full` (`<Name>` is `header.name` with underscores for
   spaces) and a `title` id that exists in `titles`.

## 4. Confirm, do not invent

1. Show the drafted facts grouped by section. Ask the user to confirm or correct them.
2. Ask explicitly for what a CV does not say:
   - the level of each skill: production, working knowledge, or none;
   - the salary expectation (amount, currency, gross or net, per month or year, contract type);
   - the earliest start date or notice period;
   - the right to work (citizenship, work permit, sponsorship);
   - languages and their levels;
   - "do not claim" limits: technologies, domains or roles the user must never claim.
3. Write the answers into `candidate_facts.md`. Change the mark of each confirmed statement to "confirmed <today>".
   Keep "from the CV, <date>" on statements that the user did not confirm, and tell the user which ones.
4. Mark salary, start date and similar statements "Not for CVs".
5. Turn each limit into a rule in `MyProfile/cv/cv_rules.yaml` (field description at the top of the file). Keep the
   `negation` anchor. Use `allow: *negation` for "no experience with X" limits, `unless: working knowledge` for
   "working knowledge only" limits. Put the date of the fact into each `message`.
6. If a correction changes CV text, change the master too.

## 5. Form answers

1. Fill `MyProfile/application_defaults.yaml` from the confirmed facts: right to work, salary, start date, languages.
   Give each answer its `source` (the section of `candidate_facts.md` and the date).
2. Set `status: confirmed` only for answers that come from confirmed facts. Set `status: ask` for every other answer
   (for example "How did you hear about this job?").

## 6. Optional photo

1. Ask whether the CV has a photo. If yes, ask for the file and copy it to `MyProfile/photo.jpg` (or `.png`).
2. Set `header.photo` in the master. If no, leave `header.photo` out.

## 7. Environment

1. Check the tools: `node --version`, `pwsh --version`, `git --version`, and Word (the registry key
   `HKEY_CLASSES_ROOT\Word.Application`).
2. If a tool is missing, tell the user what it is needed for (`${CLAUDE_SKILL_DIR}/../../reference/scripts.md`,
   "Environment") and how to install it. Do not install system programs yourself.
3. If the npm packages are missing (`cv.js` reports it), run
   `pwsh -File "${CLAUDE_SKILL_DIR}/../../scripts/install-deps.ps1"`.
4. Offer the whisper environment for call transcripts (`install-whisper.ps1`). Say that it is optional and a large
   download (about 3 GB with the model). Run it only after a yes.

## 8. First build

1. Build the full CV: `node "${CLAUDE_SKILL_DIR}/../../scripts/cv.js" MyProfile/cv/profile_full.yaml`. If a wording
   rule fails, fix the master text, not the rule.
2. Render the preview in pwsh: `pwsh -File "${CLAUDE_SKILL_DIR}/../../scripts/render-preview.ps1" -Docx
   MyProfile/cv/<output>.docx`, then read `%TEMP%\jobsearch\preview\page*.png`. Check the page count, the header and
   empty pages. Show the user the result.
3. Check that no placeholder (`<...>`) is left in `CLAUDE.md`, `MyProfile/` and `README.md`.
4. If the folder is not a git repository, run `git init`.
5. Offer the first commit. Commit only after a yes.
6. Add a work log entry to `README.md` in the notes language: the workspace was set up, the source of the facts, the
   statements that are still "from the CV", the open questions.

## 9. Next step

Tell the user how to start: share a vacancy link (or its text) and ask to analyze it; the `analyze-vacancy` skill
builds the fit table, researches the company and then makes the CV and the letter.
