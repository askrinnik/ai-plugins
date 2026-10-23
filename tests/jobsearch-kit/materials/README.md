# Test materials for jobsearch-kit

Fictional inputs and reference outputs for the jobsearch-kit tests. All people and companies are invented; the
candidate is Jordan Sample from `plugins/jobsearch-kit/templates/workspace/`.

| Path | Content |
|---|---|
| `vacancies/` | Vacancy texts, the user answers and the form questions used in the checks |
| `call/` | A two-language recruiter call: script, synthetic and live-voice audio, and what the skill must notice |
| `reference-run-2026-10-22/` | What the skills produced in the live check: application and stage folders, company research, `applications.md`, and `workspace-changes.diff` (changes to the tracked workspace files: facts, rules, work log) |
| `seeds/` | Seed files of the skill fixtures: application folders for Nordwind Pay and ExampleBank (their documents are built by the fixtures), the Nordwind Pay answers as a diff, a fictional confirmation screenshot |
| `manual-check-2026-10-22.md` | The manual check step by step, its results and the regressions found |

The reference outputs are examples of good answers, not exact expectations: model output varies. Tests compare them
with deterministic checks (files, rules, page count) and with a judge that uses a ground truth.
