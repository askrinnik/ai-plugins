# Workspace layout and settings

A workspace is the user's own folder with all job search data. The plugin holds only procedures and scripts; it
never stores user data. Run the skills with the workspace root as the current directory.

## Precedence

1. The user's request in the chat.
2. The workspace `CLAUDE.md`.
3. The plugin reference (this folder).

If the workspace `CLAUDE.md` sets a rule, use it instead of the plugin default. If it does not, use the default here.

## Layout

| Path | Content |
|---|---|
| `CLAUDE.md` | Workspace settings (see below), personal rules and the folder map |
| `README.md` | Folder map and the dated **work log** in the notes language. Add an entry at the end of every session that changes something |
| `applications.md` | Table of applications in the notes language: company, vacancy link, status, date sent, comment. It also lists analyzed vacancies that are not submitted yet |
| `MyProfile/candidate_facts.md` | **Source of truth** for facts, metrics, skill levels and "do not claim" limits. Read it before you write any CV text |
| `MyProfile/cv/cv_master.yaml` | **Single source of CV text**: header, titles, summaries, skills, jobs with tagged bullets, projects. Every CV is built from it |
| `MyProfile/cv/cv_rules.yaml` | Wording rules taken from `candidate_facts.md`. The CV build and `--lint` fail on a violation |
| `MyProfile/cv/profile_full.yaml` | Profile of the full CV; the build writes the full CV `.md` and `.docx` next to it |
| `MyProfile/application_defaults.yaml` | Standard answers for web forms (right to work, salary, start date, languages, referral), each with `status`, `source` and `note` |
| `MyProfile/photo.jpg` | Optional CV photo (`header.photo` in the master, relative to the workspace root) |
| `YYYY_MM_DD_<Company>/` | **Application folder**: `vacancy.md`, `fit-analysis.md`, `cv_profile.yaml`, the built CV, `cover-letter.md` and its builds, `form-answers.md`, employer replies (screenshots) |
| `YYYY_MM_DD_<Company>[_<Stage>]/` | **Stage folder**: one later stage (call or interview): recording, transcripts, summary, side notes, `interview-prep.md`. Its date is the stage date. Never put stage files into the application folder |
| `_Companies/<Company>/` | Company research in the notes language, one folder per company, shared by all its vacancies: `README.md`, `people.md` |

The workspace should be a git repository: the skills compare CV text with `git diff`. `git diff` compares with the
last commit (or the staged state), so commit the workspace regularly; a file that git does not track yet shows no
diff. Keep recordings out of git (add `*.mp3`, `*.m4a`, `*.wav` to `.gitignore`).

Keep scratch files outside the workspace, in `%TEMP%\jobsearch\` (for example `%TEMP%\jobsearch\preview\`).

## Workspace settings

Set these in the workspace `CLAUDE.md`. If a setting is missing, ask the user once, suggest recording the answer in
`CLAUDE.md`, and use the default until then.

| Setting | Meaning | Default |
|---|---|---|
| Conversation language | Language of every message to the user | The language the user writes in |
| Notes language | `README.md`, `applications.md`, `vacancy.md`, `fit-analysis.md`, company research, call summaries and side notes, study notes | The conversation language |
| Documents language | CVs, `cv_master.yaml`, profiles, cover letters, form answers, interview questions and prepared answers | English |
| Recruiter messages | Drafts of messages to a recruiter | The language that the recruiter uses with the user |
| Cover letter preferences | What a letter must not contain (for example the start date, the referrer, the recruiter's name) | None beyond `rules.md` |
| Writing style | Style rules per document type | The style section of `rules.md` |
| Archived files | Files that must never change (for example old Word CVs) | None |

Keep file names, commands, identifiers and quotes from documents in their original language. Do not keep parallel
copies of one file in two languages.

## Terms

- **Application folder:** the folder of one submitted or planned application.
- **Stage folder:** the folder of one later stage of an application.
- **Master:** `MyProfile/cv/cv_master.yaml`.
- **Profile:** a `cv_profile.yaml` (or `profile_full.yaml`) that selects and orders master text for one CV.
- **Facts:** `MyProfile/candidate_facts.md`.
