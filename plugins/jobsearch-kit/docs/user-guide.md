# jobsearch-kit user guide

This guide tells you which skill to use in which situation, how to start it, where it stops and waits for you, and
what it changes. For installation see the plugin `README.md`. The examples use the fictional candidate Jordan
Sample.

## Start here

Do these steps once, after you install the plugin and its npm packages (see the plugin `README.md`).

1. Create an empty folder for your workspace, for example `C:\JobSearch`.
2. Start a new Claude Code session in that folder. In the desktop app, open the Code tab, start a new session and
   select the folder. In a terminal, go to the folder and run `claude`. Do not use a session of another folder: the
   skills work in the folder of the session.
3. Say: "Set up my job search workspace. My CV is <full path to the file>." You can write in your own language. The
   `init-workspace` skill starts (you can also call it as `/jobsearch-kit:init-workspace`).
4. Answer its questions. It stops after each question and waits for you.
5. Wait for the final message. After your last answer, the skill builds your full CV and asks before the first git
   commit. Then it says "The workspace is ready", lists what it created and the facts that are still not confirmed,
   and tells you the next step. If you see "The workspace setup is not finished", or no final message at all, the
   setup is not finished: say "Continue the workspace setup" in the same folder.

The skills read their reference files and scripts from the plugin folder, which is outside your workspace. Claude
Code therefore asks for permission to read them. Allow these reads. If the prompts come too often, add a read rule for
the plugin folder only to `permissions.allow` in `~/.claude/settings.json`, for example
`"Read(//c/path/to/plugin/folder/**)"`: use the folder that the prompt names, with forward slashes and a leading
`//`. Reads of every other path still ask. The plugin `README.md`, "Troubleshooting", has the details.

When the workspace is ready, share a vacancy link: "Analyze this vacancy: <link>". Start every later session in the
same workspace folder.

## The application lifecycle

You set up the workspace once. Then every vacancy goes the same way: analysis, CV, letter, submission, calls. New
facts can come at any step. Each skill in "The skills" below has its own workflow.

| Stage | Skill | How it starts | What you decide |
|---|---|---|---|
| Set up the workspace | `init-workspace` | "Set up my job search workspace", with your CV | Settings, which facts are true, your limits |
| Analyze a vacancy | `analyze-vacancy` | "Analyze this vacancy: <link or text>" | Answer the gap questions; continue or defer |
| Tailor the CV | `adapt-cv` (called by `analyze-vacancy`) | "Continue with the CV" or "Adapt my CV for <link>" | Agree with the CV proposals |
| Cover letter | `cover-letter` | "Make a cover letter" | Check the letter |
| Submit | `submit-application` | "I am filling in the form", form screenshots | Fill in the form, tick the boxes, submit |
| Record the submission | `submit-application` | "I submitted it", a confirmation screenshot | — |
| Calls and interviews | `process-call` | "Transcribe the call <file>" | Who was on the call; correct the facts |
| New facts | `update-cv-facts` | "Add this to my facts: ..." | Confirm the wording |

Every skill stops before it does something you must decide. No skill submits a form, sends a message, ticks a box
or commits to git without your yes. The skills wait for you:

- on a fact: every fact drafted from your CV, every gap question, every fact that a letter or a call brings in; a
  fact changes only after your answer;
- on the LinkedIn research: whether to do it, and your own sign-in;
- on the decision to continue with the CV or defer;
- on each document: the CV proposals before the build, then the `.docx` of the CV and of the letter before the PDF;
- on the form: the answers marked "ask"; you fill in, tick and submit the form yourself;
- before each commit; no skill pushes.

## The facts model

- `MyProfile/candidate_facts.md` is the **source of truth**. Every CV, letter and form answer comes from it. A skill
  never writes a claim that the facts do not support.
- That is why the skills **ask instead of guessing**. If a vacancy needs something that the facts do not cover
  (for example PCI DSS), the skill marks it ❓ and asks you. Your answer becomes a dated fact.
- Every fact has a date and a source: "confirmed <date>" (you confirmed it) or "from the CV, <date>" (taken from
  your old CV and not confirmed yet).
- **Skill levels:** "production" means you used it in real work; "working knowledge" means you can work with it but
  not claim depth (for example: deploy with existing Helm charts, never set up a cluster); "none" means you must not
  claim it.
- **Do not claim:** a limit such as "no experience with Go". It becomes a **wording rule** in
  `MyProfile/cv/cv_rules.yaml`. The CV build and the letter check fail on a text that breaks a rule. An honest
  sentence such as "I have not worked with Go" passes.
- **Verb strength:** the skills keep your verbs. "Used" does not become "introduced", "took part in" does not
  become "led". A stronger verb only after you confirm that it is true.
- **Related is not the same:** "runs code reviews and onboarding" is not "mentoring", and "about 2 million requests
  per day" is not "high-load" until you say so. The skills mark such a requirement 🟡 or ❓ and ask you.
- **Versions:** if a vacancy asks for an older version than your facts name (".NET 8", and you have ".NET 10"), the
  skill marks it 🟡 and asks once whether the CV may name it. Your answer becomes a version range in the facts, and
  later vacancies inside that range need no question. An older version never covers a newer one, and products with a
  similar name are different skills (.NET Framework and .NET, AngularJS and Angular).
- **Numbers:** only the numbers that the facts state. A skill does not derive "seven years in payments" from job
  dates.

The details are in `reference/rules.md`.

## Workspace settings

The workspace `CLAUDE.md` holds your settings. The skills read them before every step, and they override the plugin
defaults. The full list is in `reference/workspace.md`, "Workspace settings".

| Setting | What it changes |
|---|---|
| Conversation language | The language of every message to you |
| Notes language | The language of `applications.md`, vacancy notes, fit analyses, company research, call summaries |
| Documents language | The language of CVs, letters and form answers |
| Recruiter messages | The language of drafts of messages to recruiters |
| Cover letter preferences | What a letter must not contain (for example the start date, the referrer, the recruiter's name) |
| Writing style | Style rules for documents |
| Archived files | Files that the skills must never change (for example old Word CVs) |

## The skills

Each skill has a workflow: its steps, who does what at each step, and where it waits for you. Legend:

- 💬 — what you say to start the skill (you can say it in your own language);
- 🧩 — another jobsearch-kit skill that this skill calls;
- 💻 — Claude in your session: it reads, writes notes and drafts texts;
- ⚙️ — a plugin script: CV and letter build, page preview, PDF export, transcription;
- 🌐 — the built-in browser of the session;
- 🙋 — a point where the skill stops and waits for you.

### init-workspace

- **Use it** once, when you start: you have no workspace yet, or an old folder that you want to move to the plugin.
- **Start:** "Set up my job search workspace in <folder>. My CV is <file>." (`.docx`, `.pdf`, text or a LinkedIn
  export).
- **It asks:** the folder; your settings (languages, letter preferences); if your CV file is in the workspace folder,
  whether to move it to `MyProfile/cv/archive/` or keep it where it is (a copy goes to the archive); then it shows
  the facts that it took from your CV and asks you to confirm or correct them; your skill levels (and, if your CV
  names versions, the version range of your main platforms), salary expectation, start date, right to work,
  languages and "do not claim" limits; an optional photo. After the first build, it shows what differs between your old CV and the new
  one, and asks you about every line that was lost or changed.
- **It stops and waits:** after each of these questions, before the first commit, and before it installs the
  optional transcription environment.
- **It creates:** the workspace from the empty template; `candidate_facts.md`, the master CV, the wording rules, the
  form answers; the first full CV (`.md` and `.docx`) with a preview; a git repository.
- **It ends** with "The workspace is ready" and a list: what it created, the facts that are still "from the CV", the
  open questions, the next step. If a step is left (for example no commit), it says "The workspace setup is not
  finished" and names the steps that are left.
- **If it stopped halfway:** start it again in the same folder ("Continue the workspace setup"). It shows the steps
  that are done and continues from the first step that is not done.
- **It never:** marks a fact as confirmed that you did not confirm; commits without your yes; installs system
  programs.
- **Problems:** if a fact from your CV is wrong, say so; it stays "from the CV" until you confirm it. If Node, Word
  or `pwsh` is missing, the skill tells you what to install.

**Workflow.**

```
💬 "Set up my job search workspace. My CV is <file>."
│
├─ 1. Folder ────────────────── 🙋 where the workspace goes
│                               (folder not empty → 🙋 continue?
│                                · an unfinished setup → continue from the first step that is left)
│                               💻 copies the empty workspace template
├─ 2. Settings ──────────────── 🙋 languages · letter preferences · writing style · archived files
│                               💻 writes them into CLAUDE.md
├─ 3. Import your CV ────────── 🙋 move your CV file to MyProfile/cv/archive/? (no → a copy goes there)
│                               💻 candidate_facts.md and the master CV; every fact is "from the CV"
├─ 4. Confirm the facts ─────── 🙋 confirm or correct the facts · skill levels · version ranges
│                                  · salary · start date · right to work · languages · "do not claim" limits
│                               💻 "confirmed <date>" · each limit becomes a wording rule
├─ 5. Form answers ──────────── 💻 application_defaults.yaml from the confirmed facts
├─ 6. Photo ─────────────────── 🙋 a photo in the CV? (optional)
├─ 7. Environment ───────────── ⚙️ checks Node, pwsh, git, Word and the npm packages
│                               (a tool is missing → it tells you what to install)
│                               🙋 install the transcription environment? (optional, about 3 GB)
├─ 8. First build ───────────── ⚙️ full CV .md and .docx · page preview · comparison with your old CV
│                               🙋 every line that was lost or changed (build again until clean)
│                               🙋 "yes, commit"
└─ 9. Finish ────────────────── 💻 "The workspace is ready": what it created, facts still "from the CV",
                                   the next step
                                (a step is left → "The workspace setup is not finished")
```

### analyze-vacancy

- **Use it** for every vacancy that you consider. Use `adapt-cv` alone only when you already know the fit and want
  just a CV.
- **Start:** "Analyze this vacancy: <link>", or paste the text, or attach a screenshot.
- **It asks:** first, if the session has a browser: whether to research the people and the company on LinkedIn, and
  who found the vacancy (referral or not). Without a browser it does not stop for this, and asks who found the
  vacancy at the end. Later: gap questions about requirements that your facts do not cover.
- **LinkedIn:** if you say yes, the skill opens the LinkedIn sign-in page in the browser of the session and waits.
  You sign in yourself; the skill never types a login or a password. The work in your account is read only: the
  skill opens, searches and reads pages, and never connects, follows, messages, likes, comments, applies, saves or
  edits anything. LinkedIn may show the people whose profiles it opens that you viewed them (by your privacy
  settings). If you say no, the company notes say that LinkedIn was not researched.
- **It stops and waits** after the first questions (and the LinkedIn sign-in, if you want it), and after the fit
  table and the company research: "continue with the CV or defer?"
- **It creates:** an application folder `YYYY_MM_DD_<Company>/` with `vacancy.md` and `fit-analysis.md`; company
  research in `_Companies/<Company>/README.md`; a "not submitted" row in `applications.md`; a work log entry. Your
  answers go to the facts through `update-cv-facts`.
- **It never:** guesses a gap; invents company facts (if nothing is found, it says so); sends LinkedIn requests or
  messages; commits without your yes.
- **Problems:** if a page needs a sign-in (LinkedIn Jobs), sign in in the built-in browser when the skill asks. If you
  applied to the company before, the skill reminds you.

**Workflow.**

```
💬 "Analyze this vacancy: <link>" (or the text, or a screenshot)
│
├─ 1. Read the vacancy ──────── 🌐 the vacancy page (it needs a sign-in → 🙋 you sign in)
│                               🙋 research LinkedIn? · who found the vacancy?
│                               (LinkedIn yes → 🙋 you sign in yourself; the skill only reads)
│                               (no browser → no stop here; "who found it" comes in step 4)
│                               💻 YYYY_MM_DD_<Company>/vacancy.md · earlier applications to the company
├─ 2. Fit table ─────────────── 💻 fit-analysis.md: ✅ 🟡 ❌ ❓ per requirement, fit in percent
│                               🙋 gap questions (❓ only) → 🧩 update-cv-facts
├─ 3. Research the company ──── 💻 🌐 registry, finances, salaries, real stack, people, news
│                               → _Companies/<Company>/README.md
├─ 4. Report ────────────────── 💻 a "not submitted" row in applications.md
│                               🙋 "continue with the CV or defer?"
│                               (defer → the reason in applications.md, step 6)
├─ 5. Documents ─────────────── 🧩 adapt-cv (its own workflow below)
│                               🧩 cover-letter: the vacancy asks for a letter → no question;
│                                  else 🙋 "is a letter needed?"
│                               🧩 submit-application, when you are ready to submit
└─ 6. Log ───────────────────── 💻 work log in README.md · applications.md
                                🙋 "yes, commit" (never pushed)
```

**Example.**

> **You:** Analyze this vacancy. I only have the text: Senior Java Engineer, Nordwind Pay, Northport ...
>
> **Claude:** Fit about 85%. Go ❌, Kubernetes 🟡 (working knowledge), PCI DSS ❓. Company: nothing found about
> Nordwind Pay; verify the entity in the register. Questions: 1. Any PCI DSS experience? 2. Merchant onboarding or
> payouts? 3. Ready to relocate to Northport? 4. Who found the vacancy? Continue with the CV or defer?
>
> **You:** 1. No. 2. No. 3. Yes, at my own cost. 4. Myself. Continue with the CV.

### adapt-cv

- **Use it** for a tailored CV. `analyze-vacancy` calls it for you; call it alone when you skip the analysis.
- **Start:** "Adapt my CV for this vacancy: <link or text>".
- **It asks:** gap questions (only when called alone); then it shows the CV proposals (what to lead with, reorder,
  cut, which keywords).
- **It stops and waits** for you to agree with the proposals (nothing is built before that), and for you to check
  the built CV before it makes the PDF.
- **It creates:** `cv_profile.yaml`, the CV `.md` and `.docx` in the application folder (it starts from your newest
  tailored CV, or from the full CV); a preview check; a "not submitted" row in `applications.md`.
- **Then it asks you to check the CV** and sends you the `.docx`. Ask for changes, or confirm it: then it makes the
  PDF (with working links) and sends it to you. If the CV changes later, it makes the PDF again.
  `submit-application` checks before you submit that the PDF is not older than the `.docx`.
- **It never:** adds a claim beyond the facts ("high-load", "mentors" without a fact); weakens a wording rule to pass
  the build.
- **Problems:** if Word has the `.docx` open, close it when the skill asks.

**Workflow.**

```
💬 "Adapt my CV for this vacancy: <link or text>" (or analyze-vacancy calls it)
│
├─ 1. Inputs ────────────────── 🌐 the vacancy page, or vacancy.md and fit-analysis.md of analyze-vacancy
│                               💻 starts from your newest tailored CV, or from the full CV
│                               (the master CV misses a confirmed fact → 🧩 update-cv-facts first)
├─ 2. Gaps and proposals ────── 💻 requirement table ✅ 🟡 ❌ ❓ (only when called alone)
│                               🙋 gap questions (only when called alone) → 🧩 update-cv-facts
│                               🙋 agree with the proposals: what to lead with, reorder, cut; keywords
│                               (nothing is built before that)
├─ 3. Profile ───────────────── 💻 cv_profile.yaml in the application folder
├─ 4. Build and check ───────── ⚙️ CV .md and .docx · wording rules · page preview
│                               (Word has the .docx open → 🙋 close it)
└─ 5. Check and PDF ─────────── 🙋 check the .docx (changes → step 4 again)
                                ⚙️ CV PDF with working links
                                called alone: 🙋 a cover letter? · work log · 🙋 "yes, commit"
                                (called by analyze-vacancy → it offers the letter and writes the log)
```

**Example.**

> **You:** Adapt my CV for this vacancy: Senior Backend Engineer, ExampleBank ... (text)
>
> **Claude:** Go ❌, Kubernetes 🟡, Redis ❓, mentoring 🟡 (your facts name code reviews and onboarding, not
> mentoring). Proposals: lead with the payment API (about 2 million requests per day), put the settlement bullet
> second, add the keywords Spring Boot, Kafka, PostgreSQL. Questions: any Redis experience? Is "mentoring" true for
> you? Nothing is built yet.
>
> **You:** No Redis. No mentoring. Build it.

### cover-letter

- **Use it** when a vacancy or a form asks for a letter or a motivation text.
- **Start:** "Make a cover letter for <company>".
- **It asks:** a fact that the letter needs and the facts do not have.
- **It creates:** `cover-letter.md` (one line per paragraph, so that you can paste it into a form) and the `.docx`;
  one page, 250–350 words.
- **It stops and waits** for you to check the letter: it sends you the `.docx`. Ask for changes, or confirm it: only
  then it makes the PDF and sends it to you.
- **It never:** names gaps as strengths; derives numbers from dates; writes what your letter preferences forbid
  (start date, referrer, recruiter's name).
- **Problems:** without company research the skill uses only the vacancy text and tells you so; run
  `analyze-vacancy` first for a better "why this company".

**Workflow.**

```
💬 "Make a cover letter for <company>" (or analyze-vacancy or adapt-cv calls it)
│
├─ 1. Inputs ────────────────── 💻 vacancy.md · fit-analysis.md · _Companies/<Company>/ · facts · tailored CV
│                               (no company research → only the vacancy text; it tells you so)
├─ 2. Write ─────────────────── 💻 cover-letter.md: one line per paragraph, 250–350 words
│                               🙋 a fact that the letter needs and the facts do not have
│                                  → 🧩 update-cv-facts
├─ 3. Wording rules ─────────── ⚙️ lint (a rule fails → the text changes, never the rule)
├─ 4. Build and check ───────── ⚙️ .docx · one-page check
└─ 5. Check and PDF ─────────── 🙋 check the .docx (changes → steps 3–4 again)
                                ⚙️ letter PDF
                                called alone: work log · 🙋 "yes, commit"
```

**Example.**

> **You:** Make a cover letter for Nordwind Pay.
>
> **Claude:** The letter is ready: 290 words, one page, `.docx` attached. It names the gaps honestly ("I have not
> worked with PCI DSS or Go") and does not mention your start date or the referrer. Check the sentence about the
> settlement project. Is the letter correct? Then I make the PDF.
>
> **You:** It is correct. Make the PDF.
>
> **Claude:** The PDF is ready: one page, attached.

### submit-application

- **Use it** twice: before you submit (check) and after you submit (record).
- **Start before:** "I am filling in the form now", with the form questions or screenshots.
  - **It checks:** the CV and letter are current; it exports the PDFs and checks the links; it shows the referral link
    if there is one.
  - **It drafts:** the form answers from `application_defaults.yaml` (salary, start date, right to work); a
    motivation answer.
  - **It asks:** every answer with `status: ask` (for example "How did you hear about us?").
  - **It stops:** you fill in the form, tick the boxes and submit.
- **Start after:** "I submitted it", with the confirmation screenshot or e-mail.
  - **It records:** `Confirmation_<date>.png` in the application folder, the date in `applications.md`, a work log
    entry.
- **It never:** clicks, ticks, submits or sends anything.

**Workflow.**

```
Before you submit
💬 "I am filling in the form now", with the form questions or screenshots
│
├─ 1. Find the application ──── 💻 the application folder and its row in applications.md
├─ 2. Check the files ───────── ⚙️ the CV text is current (it changed → 🙋 accept the change?)
│                               ⚙️ PDFs not older than the .docx · links kept · pages
│                               (Word has a file open → 🙋 close it)
├─ 3. Check the link ────────── 💻 the referral link, if there is one: submit through it only
├─ 4. Form answers ──────────── 💻 answers from application_defaults.yaml · a motivation text
│                               🙋 every answer marked "ask" (for example "How did you hear about us?")
│                               💻 which file goes into which upload field
├─ 5. Consents ──────────────── 💻 which boxes are required and which are optional
└─ 🙋 you fill in the form, tick the boxes and submit

After you submit
💬 "I submitted it", with the confirmation screenshot or e-mail
│
├─ 1. Confirmation ──────────── 💻 Confirmation_<date>.png in the application folder
├─ 2. Records ───────────────── 💻 "sent <date>" in applications.md · work log
│                               (something is unknown, for example who shared the link → 🙋)
│                               (a form answer differs from the defaults → 🙋 update the defaults?)
└─ 3. Commit ────────────────── 🙋 "yes, commit" (never pushed)
```

**Example.**

> **You:** I am filling in the ExampleBank form. Questions: salary, start date, work permit, how did you hear about
> us?
>
> **Claude:** The PDFs are current and keep your links. Answers: 5000 EUR gross per month; one month after an offer;
> no work permit needed (citizen). "How did you hear about us?" — what should I write? Upload the CV PDF as the
> resume and the letter PDF as the cover letter. The data processing box is required; the talent pool box is your
> choice.
>
> **You:** (later) I submitted it. Here is the confirmation screenshot.
>
> **Claude:** Saved as `Confirmation_2026_10_23.png`; `applications.md` shows "sent 2026-10-23".

### process-call

- **Use it** after a recruiter call, an interview or a talk with a former client, when you have a recording.
- **Start:** "Transcribe the call <file>".
- **It asks:** the company, who spoke (names and roles), the languages, when the language changed (if two languages),
  the date.
- **It creates:** a stage folder (`YYYY_MM_DD_<Company>_<Stage>/`) with the recording (kept out of git), the raw and
  the cleaned transcript, a summary with risks and next steps, side notes; it updates the company notes and
  `applications.md`.
- **It stops and waits** when the call contradicts your facts (for example you named a different salary): it asks;
  the facts change only after your answer.
- **It never:** changes the facts because of something said on the call.
- **Problems:** transcription needs the whisper environment (`install-whisper.ps1`). If the language switch is wrong,
  tell the skill the time.

**Workflow.**

```
💬 "Transcribe the call <file>"
│
├─ 1. Ask ───────────────────── 🙋 company · who spoke · languages and the switch time · date
│                               (only what your message and the file name do not say)
├─ 2. Stage folder ──────────── 💻 YYYY_MM_DD_<Company>_<Stage>/; the recording moves there
├─ 3. Transcribe ────────────── ⚙️ whisper, in the background
├─ 4. Write the files ───────── 💻 raw text · transcript with speakers · summary · side notes
├─ 5. Facts and people ──────── 🙋 the call contradicts your facts → which is right?
│                                  → 🧩 update-cv-facts
│                               🌐 new people on LinkedIn (🙋 it asks first; it only reads)
│                               💻 company notes
└─ 6. Records ───────────────── 💻 applications.md · work log
                                🙋 "yes, commit" (the recording stays out of git)
```

**Example.**

> **You:** Transcribe the call call.mp3: Anna, recruiter of Nordwind Pay, English, then my native language, today.
>
> **Claude:** The call passed; next is a technical interview with Marek, invitation by Friday. Main risk: you said
> you set up the clusters yourself, but your facts say Kubernetes working knowledge only. You named 5,500 EUR; your
> facts say 5000. Which is right? Your facts are unchanged until you answer.
>
> **You:** The Kubernetes claim was an exaggeration. The salary stays 5000.

### update-cv-facts

- **Use it** whenever you learn or correct something about yourself: a new skill, a result, a limit, a new salary
  expectation.
- **Start:** "Add this to my facts: ..."
- **It asks:** only what is missing: the period, your role, numbers, whether it may go into a CV.
- **It changes:** `candidate_facts.md` (with a date); the master CV; the wording rules (for a limit); the form
  answers; it rebuilds the full CV (`.md` and `.docx`) and shows the change; it checks your unsent tailored CVs and
  offers to rebuild them.
- **It never:** makes your verb stronger; rebuilds the CV of an application that you already submitted.

**Workflow.**

```
💬 "Add this to my facts: ..." (or another skill calls it)
│
├─ 1. Get the fact ──────────── 🙋 only what is missing: period, your role, numbers, CV or not
├─ 2. Facts ─────────────────── 💻 candidate_facts.md, with the date
├─ 3. Master CV ─────────────── 💻 the bullet or the skill text (only if the CV text changes)
├─ 4. Wording rule ──────────── 💻 cv_rules.yaml (only for a limit)
├─ 5. Full CV ───────────────── ⚙️ full CV .md and .docx · 💻 shows you the change
├─ 6. Unsent CVs ────────────── ⚙️ checks each unsent tailored CV against the new fact
│                               🙋 build it again? (a submitted CV never changes)
├─ 7. Form answers ──────────── 💻 application_defaults.yaml
└─ 8. Log ───────────────────── 💻 work log · 🙋 "yes, commit"
```

**Example.**

> **You:** Add this to my facts: at Example Payments I have used Redis in production since 2022 as a cache for the
> payment API; p95 fell from 300 ms to 120 ms. It may go into CVs.
>
> **Claude:** Recorded with today's date. New CV bullet: "Use Redis in production as a cache for the payment API; p95
> response time fell from 300 ms to 120 ms." The full CV is rebuilt (`.md` and `.docx`). Your unsent CV for Sample
> Logistics would get the bullet too: rebuild it? The submitted ExampleBank One CV stays as it was sent.

## Situations

| I want to ... | Do this |
|---|---|
| Start using the plugin | "Start here" above: a new session in an empty folder, then `init-workspace` with your current CV |
| Apply to a vacancy from a link | `analyze-vacancy` with the link; answer the questions; continue with the CV; `cover-letter` if needed; `submit-application` before and after you submit |
| Only adapt the CV | `adapt-cv` with the link or text |
| Use a vacancy that is a screenshot or text | `analyze-vacancy` with the screenshot or the pasted text; say that there is no link |
| Answer a recruiter who wrote to me | `analyze-vacancy` with the vacancy from the message; ask Claude to draft the reply (it uses the "Recruiter messages" language); you send it |
| Process a call I had | `process-call` with the recording |
| Record something new I learned about myself | `update-cv-facts` |
| Change my salary expectation | `update-cv-facts` ("my salary expectation is now ..."); it also changes the form answers |
| Check everything before I submit | `submit-application` ("I am filling in the form") |
| Keep an older application as it was sent | Nothing: the skills never rebuild the CV of a submitted application. Record each submission with `submit-application` so that the skills know it was sent |

## Keep this guide current

If a skill changes how it starts, what it asks, where it stops or what it changes, change this guide in the same
change.
