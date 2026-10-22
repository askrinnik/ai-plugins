# Manual end-to-end check of jobsearch-kit, 2026-10-22

What was checked by hand, step by step, and what came out. The automated tests should cover every step below.

Setup: a workspace copied from `plugins/jobsearch-kit/templates/workspace/` (fictional candidate Jordan Sample),
`git init` and one commit; Claude Code CLI started in it with `--plugin-dir <clone>/plugins/jobsearch-kit`;
`JOBSEARCH_WHISPER` pointing to an existing whisper environment. Model: Sonnet. The reference outputs are in
`reference-run-2026-10-22/`.

| # | Check | How | Expected | Result |
|---|---|---|---|---|
| 0 | Session starts | CLI with `--plugin-dir` | Interactive session | ✅ |
| 1 | Plugin loads | Type `/jobsearch-kit:` | Six skills listed | ✅ |
| 2 | Vacancy and fit table | `analyze-vacancy` with the Nordwind Pay text (`vacancies/nordwind-pay.md`) | Application folder with `vacancy.md` and `fit-analysis.md`; Go ❌, Kubernetes 🟡; questions only about what the facts do not cover | ✅ Claude Code asked for permission to read the plugin reference outside the workspace; the skill used an undefined status ❓ (now defined) |
| 3 | Company research and stop | Continuation of 2 | `_Companies/<Company>/README.md` with sources and dates; nothing invented for an unknown company; row in `applications.md`; the skill stops and asks whether to make the CV | ✅ |
| 4 | Facts and CV proposals | Answers from `vacancies/nordwind-pay.md` | Answers recorded in `candidate_facts.md` without stronger wording; matching rules in `cv_rules.yaml`; CV proposals shown; nothing built until the user agrees | ✅ The skill refused "high-load" and "mentors" because the facts do not support them |
| 5 | CV build | Answer "yes" | `cv_profile.yaml`, CV `.md` and `.docx`; preview checked; one page; wording rules pass | ✅ The template listed "Mentoring" without a fact (fixed); the full CV was rebuilt without `.docx` (fixed) |
| 6 | Cover letter | "Make a cover letter" | One page, 250–350 words; gaps named honestly; no start date, referrer or recruiter name | ✅ The letter derived periods from job dates ("the last seven years in payments"); a rule now forbids derived numbers |
| 7 | Call processing | `process-call` with `call/call-live-voice-en-ru.mp3`; languages en and ru, switch time "not remembered" | Separate stage folder; four files (raw, transcript, summary, side talk); all items of `call/README.md` noticed; recording ignored by git | ✅ Detection error corrected with `--switch` |
| 8 | Facts after the call | User answers: exaggeration, salary stays 5000, start one month | `candidate_facts.md` unchanged by the call | ✅ |

## Headless check of the same day

`claude -p --plugin-dir ...` with all confirmations given in the prompt:

1. Skill loading: all six skills visible; `${CLAUDE_SKILL_DIR}` resolves to the real plugin path.
2. `update-cv-facts` with the Redis fact (`vacancies/examplebank.md`): facts, master and full CV updated. Found:
   the verb "used" became "introduced" (fixed by a rule in the skill).
3. `adapt-cv` → `cover-letter` → `submit-application` part 1 for ExampleBank: CV, letter and PDFs built, form
   answers drafted, the `status: ask` question left to the user. Found: no `applications.md` row from `adapt-cv`
   alone, backslash paths broke in the Bash tool, `git diff` silent on untracked files, missing guidance for a
   vacancy given as text and for missing company research (all fixed in 0.1.1).

## Regressions to keep tested

| Regression | Where it showed | Expected now |
|---|---|---|
| A fact's verb made stronger ("used" → "introduced") | update-cv-facts, then the letter | The verb of the fact is kept; a stronger one only after the user confirms |
| Numbers derived from dates | cover-letter | Only numbers that the facts state |
| Undefined fit status ❓ | analyze-vacancy | ❓ means "not in the facts, question to the user" and is replaced after the answer |
| Full CV rebuilt without `.docx` | update-cv-facts | Both `.md` and `.docx` exist |
| No `applications.md` row after adapt-cv alone | adapt-cv | A "not submitted" row exists |
| Template claims without facts ("Mentoring") | template | Every template CV claim is backed by the template facts |
