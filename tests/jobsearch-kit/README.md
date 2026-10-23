# jobsearch-kit tests

Developer tests of the `jobsearch-kit` plugin. This folder is outside `plugins/`, so it is not installed with the
plugin.

There are two kinds of tests:

- **Script tests** start no model session. They take seconds and do not use the usage limit. Run them after every
  change of a script or of the workspace template.
- **Skill tests** run the skills in headless Claude Code sessions on a fresh fictional workspace and check the
  results. They take minutes and use the Claude usage limit.

| Path | Content |
|---|---|
| `config.json` | Shared settings: the seed workspace of the tests (`materials/workspace-jordan`) and the plugin folder |
| `scripts/Test-Scripts.ps1` | Script tests |
| `scripts/unit/` | The script tests and their expected outputs |
| `scripts/Run-Tests.ps1` | Runs skill fixtures |
| `scripts/Collect-Tests.ps1` | Judges, collects metrics, writes the history and the report of a run |
| `scripts/lib/` | Workspace and session helpers, checks, judge, history and report |
| `fixtures/<name>/` | One skill test per folder |
| `run-history.csv` | One row per fixture repetition of every run (tracked) |
| `reports/<run id>.md` | One report per run (tracked) |
| `runs/<run id>/` | Raw outputs of a run: answers, transcripts, judge texts (not tracked) |
| `materials/` | Fictional inputs and reference outputs (see `materials/README.md`) |
| `tools/` | Tools that make test materials (`New-CallAudio.ps1`) |

## Script tests

```powershell
pwsh -File tests\jobsearch-kit\scripts\Test-Scripts.ps1 [-SkipWord] [-SkipAudio]
```

- Node tests (`node --test`, `scripts/unit/*.test.js`): the workspace root search, the CV build and every section
  kind, the wording rules, the error messages, `build-cv.js`, `build-letter.js`, the consistency check of the seed
  (every CV claim backed by a fact), and the check that the plugin template is an empty skeleton that builds.
- PowerShell tests (`scripts/unit/scripts.Tests.ps1`): `folder-variable.ps1` (on a throwaway user variable that the
  test removes), `New-CallAudio.ps1`, and the Word scripts `export-pdf.ps1` and `render-preview.ps1`.
- Without the Word tests the run takes a few seconds. If Word is not installed, the Word tests are skipped with a
  message.
- The tests need the npm packages of the plugin (`plugins/jobsearch-kit/scripts/install-deps.ps1`). Temporary files go
  to `%TEMP%\jobsearch-tests\unit`.

Three checks compare the seed workspace with stored data:

- `scripts/unit/expected/` holds the expected full CV of the seed. If you change the seed CV on purpose, run
  `Test-Scripts.ps1 -UpdateExpected` and review the diff.
- `scripts/unit/template-claims.yaml` lists, for every text unit of the seed master CV, the phrases of
  `candidate_facts.md` that back it. A new CV claim needs a backing fact and an entry there.
- Every wording rule of the seed needs a case (a claim and an honest text) in `RULE_CASES` of `scripts/unit/cv.test.js`.

## Skill tests

```powershell
pwsh -File tests\jobsearch-kit\scripts\Run-Tests.ps1 -Fixture <names or masks> -Note "<what changed>" [-DryRun]
```

| Parameter | Meaning |
|---|---|
| `-Fixture` | Fixture names or `-like` masks, comma-separated. Default: all fixtures except the slow ones |
| `-Note` | What changed since the last run; goes into the history and the report. Required unless `-DryRun` |
| `-DryRun` | Prints the plan (sessions, expected time) and the session command line; runs nothing |
| `-Model` | Model of the test sessions; default `sonnet` |
| `-Effort` | Effort level of the test sessions; default: the CLI default |
| `-JudgeModel` | Model of the judge; default `sonnet` |
| `-Repetitions` | Overrides `repetitions` of every selected fixture |
| `-Keep` | Keeps every workspace. Without it, only the workspaces of failed repetitions are kept |
| `-IncludeSlow` | Lets a mask select slow fixtures. A slow fixture named exactly always runs |

What one fixture repetition does:

```
seed workspace (config.json "seed") + fixture seed files
  -> git init, one commit            (%TEMP%\jobsearch-tests\<run id>\<fixture>-r<n>)
  -> turn 01: claude -p              -> checks of turn 01 -> judge input of turn 01
  -> turn 02: claude -p --resume     -> checks of turn 02 -> ...
  -> judge, metrics -> run-history.csv, reports\<run id>.md
```

- Every session runs with `--plugin-dir plugins/jobsearch-kit`, so the tests run the working tree, not the installed
  plugin. The plugin folder is added with `--add-dir`, so the skills can read the plugin reference.
- Every session is isolated from the developer's own setup: `--setting-sources project,local` (no user settings,
  installed plugins, hooks or permissions), `--strict-mcp-config` (no MCP servers), the user `CLAUDE.md` excluded with
  `claudeMdExcludes`, and the variables of a hosting Claude Code session removed. `JOBSEARCH_WHISPER` and
  `JOBSEARCH_DEPS` pass through.
- Every session gets an explicit `--allowedTools` list, so it never waits for a permission prompt; a tool that is not
  in the list is denied. The report counts the denials.
- The judge is a headless session without tools. It scores the material of a turn against the ground truth.
- A repetition passes if every session ends without an error, every check passes, and every judged turn reaches the
  minimum score.
- The report compares each fixture with the previous run that ran it: `REGRESSION` (lower pass rate, or a mean
  score lower by more than the noise), `improvement` (the opposite), `within noise`, or `first run`. The noise of the
  score is the larger of 1 point and two standard deviations of the scores of both runs.
- A failed check prints the check, the expected and the actual value, and the workspace stays for inspection.

### Fixture format

```
fixtures/<name>/
  prompt.txt              the prompt of a one-turn fixture, or
  turns/01.txt, 02.txt    the turns of a multi-turn fixture (02 and later continue the session with --resume)
  checks/01.json          deterministic checks after turn 01 (optional; one file per turn)
  ground-truth/01.md      the judge's ground truth for turn 01 (optional; "Max score: N" is required)
  ground-truth.md         same as ground-truth/01.md
  fixture.json            settings (optional)
  seed/                   files copied over the seed workspace (optional)
  seed.diff               a diff applied to the seed workspace with git apply (optional)
```

A new test is a new folder; no script change is needed. Placeholders in prompts, check paths and patterns, and
`seedCopy` targets: `{{today}}` (`yyyy-MM-dd`), `{{date}}` (`yyyy_MM_dd`), `{{workspace}}` (the workspace path with
forward slashes), `{{include:<path in the repository>#<n>}}` (the n-th fenced code block of that file, so that a
prompt uses a vacancy text or the user answers of `materials/` without a copy). In `seedCommands`, `{{plugin}}` is the
plugin folder.

Shared seeds are in `materials/seeds/`: an application folder with its tailored CV for Nordwind Pay and for
ExampleBank, the Nordwind Pay answers as a diff of the facts and rules (`nordwind-pay.diff`), and a fictional
confirmation screenshot. Fixtures take them with `seedCopy` and `seedDiffs`, and build the documents with
`seedCommands`, so that a seed always matches the current seed master.

`fixture.json`:

| Field | Meaning | Default |
|---|---|---|
| `description` | What the fixture proves | |
| `repetitions` | Repetitions per run | 1 |
| `allowedTools` | The whole tool list of the sessions | Read, Write, Edit, Glob, Grep, Skill, Bash, PowerShell, TodoWrite, WebSearch, WebFetch |
| `addAllowedTools` | Tools added to the default list | |
| `slow` | Leave the fixture out of a default run | false |
| `requires` | `word`, `whisper`: skip the fixture with a message when it is missing | |
| `timeoutMinutes` | Time limit of one turn | 20 |
| `seedCopy` | `[{ "from": <path in the repository>, "to": <path in the workspace> }]`, files or folders | |
| `seedRemove` | Paths removed from the seed workspace | |
| `emptySeed` | Start from an empty folder without git: no seed workspace, no seed commit; only `seedCopy` and `seed/` files (for `init-workspace`) | false |
| `seedDiffs` | Diffs (paths in the repository) applied with `git apply` after the seed files | |
| `seedCommands` | pwsh commands run in the workspace before the seed commit (for example a CV build) | |
| `judge.files` | Workspace globs whose content the judge gets with the answer | |
| `judge.minScore` | Minimum judge score of a turn (summed over the judged turns) | the maximum |

Checks (`checks/NN.json`, an array). Paths are globs relative to the workspace, with forward slashes; `*` also
matches `/`. Every check may have a `name`; patterns are .NET regular expressions, case-insensitive unless
`"ignoreCase": false`.

| `type` | Fields | Passes when |
|---|---|---|
| `exists` / `absent` | `path` | a file or folder matches / nothing matches |
| `count` | `path`, `count` | exactly `count` files and folders match |
| `unchanged` / `changed` | `path` | `git status` shows no change / a change since the seed commit (`.` = the whole workspace) |
| `contains` | `path`, `pattern` | at least one file matches and every matching file contains the pattern |
| `not-contains` | `path`, `pattern` | no matching file contains the pattern |
| `answer-contains` / `answer-not-contains` | `pattern` | the session's answer of this turn contains / does not contain the pattern |
| `lint` | `path` | `cv.js --lint` passes for the matching files with the workspace rules |
| `pages` | `path`, `max` | every matching `.docx` has at most `max` pages (Word; skipped without Word) |
| `ignored` | `path` | every matching file is ignored by git |
| `tool-input` / `no-tool-input` | `pattern` | an input of the session's tool calls so far matches / none matches. Each input reads `<tool>: <input JSON>`, for example `Skill: {"skill":"jobsearch-kit:adapt-cv"}` |
| `script` | `file`, `args` | `pwsh -File <file> -Workspace <ws> -AnswerFile <file> <args>` exits with 0. `file` is relative to the fixture folder or to the repository |

Shared check scripts are in `scripts/checks/`: `Test-Letter.ps1` (front matter, one line per paragraph, 250–350
body words, no number derived from dates) and `Test-Pdfs.ps1` (every `.docx` has a PDF that is not older; the CV PDF
keeps every contact link).

Ground truth (`ground-truth/NN.md`): a list of scored items and a line `Max score: N`. The judge gives 1 point per item
and counts false positives (claims that the material does not back). Base ground truths on `materials/`.

### Fixtures

| Fixture | What it proves |
|---|---|
| `smoke` | The plugin loads, the seven skills are visible, `${CLAUDE_SKILL_DIR}` resolves |
| `selftest-stop` | Framework self-test: a check after turn 1 proves that the session stopped; the judge pipeline works |
| `analyze-vacancy-text` | Fit table and company research for a vacancy given as text; the skill stops before the CV; the answers reach the facts and the rules |
| `analyze-vacancy-defer` | The user defers: the reason is recorded, no CV |
| `analyze-vacancy-earlier-application` | An earlier application to the same company is mentioned; the company notes are kept |
| `update-cv-facts-verb-strength` | The verb of a fact is kept ("used", not "introduced"); the full CV is rebuilt with `.md` and `.docx` |
| `update-cv-facts-limit` | A "no experience with X" fact becomes a rule that lets honest negations through |
| `update-cv-facts-unsent-cvs` | The unsent tailored CV is checked; the submitted one stays as sent |
| `adapt-cv-text` | Proposals first, no build until the user agrees; then a one-page CV and a "not submitted" row |
| `adapt-cv-first-profile` | Without an earlier application, the profile starts from `profile_full.yaml` |
| `cover-letter-basic` | Letter format, length, one page, no derived numbers, no start date, referrer or recruiter |
| `cover-letter-no-research` | Without company research the letter uses the vacancy only, and the skill says so |
| `submit-application-prepare` | PDFs with links, form answers from the defaults, the "ask" question left to the user, nothing submitted |
| `submit-application-record` | The confirmation is saved, the row gets the date, a work log entry is written |
| `init-workspace-docx` | A workspace from zero with a fictional base CV (`materials/base-cv/`): settings, confirmed facts, rules, form answers, a full CV that builds, no template data |
| `init-workspace-pdf` | The same from a `.pdf` base CV |
| `process-call-two-languages` | A two-language call (synthetic audio): stage folder, four files, recording out of git, the planted items found, facts unchanged |
| `process-call-live-voice` | The same with the live-voice recording, to compare the scores |
| `end-to-end` (slow) | The whole path from an empty folder to the processed call in one workspace |

### Rules for skill tests

- Use `sonnet` for test sessions and the judge.
- During development run a fixture with 1 repetition. Run its `repetitions` (usually 3) once, as the final check
  before the commit.
- Give a fixture only the tools its skill needs (`allowedTools` or the default list).
- Keep fictional data only: the seed candidate, the fictional companies of `materials/`.
- Commit `run-history.csv` and the new report with the change that the run checked.
