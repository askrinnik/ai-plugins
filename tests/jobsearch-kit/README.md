# jobsearch-kit tests

Developer tests of the `jobsearch-kit` plugin. This folder is outside `plugins/`, so it is not installed with the
plugin.

| Path | Content |
|---|---|
| `config.json` | Shared settings: the seed workspace of the tests and the plugin folder |
| `scripts/Test-Scripts.ps1` | Script tests without model sessions |
| `scripts/unit/` | The script tests and their expected outputs |
| `materials/` | Fictional inputs and reference outputs (see `materials/README.md`) |
| `tools/` | Tools that make test materials (`New-CallAudio.ps1`) |

## Script tests

Fast tests of the plugin scripts. They start no model session, so they do not use the usage limit. Run them after
every change of a script or of the template:

```powershell
pwsh -File tests\jobsearch-kit\scripts\Test-Scripts.ps1 [-SkipWord] [-SkipAudio]
```

- Node tests (`node --test`, `scripts/unit/*.test.js`): the workspace root search, the CV build and every section
  kind, the wording rules, the error messages, `build-cv.js`, `build-letter.js`, and the template consistency check.
- PowerShell tests (`scripts/unit/scripts.Tests.ps1`): `folder-variable.ps1` (on a throwaway user variable that the
  test removes), `New-CallAudio.ps1`, and the Word scripts `export-pdf.ps1` and `render-preview.ps1`.
- Without the Word tests the run takes a few seconds. If Word is not installed, the Word tests are skipped with a
  message.
- The tests need the npm packages of the plugin (`plugins/jobsearch-kit/scripts/install-deps.ps1`). Temporary files go
  to `%TEMP%\jobsearch-tests\unit`.

Two checks compare the seed workspace with stored data:

- `scripts/unit/expected/` holds the expected full CV of the seed. If you change the seed CV on purpose, run
  `Test-Scripts.ps1 -UpdateExpected` and review the diff.
- `scripts/unit/template-claims.yaml` lists, for every text unit of the seed master CV, the phrases of
  `candidate_facts.md` that back it. A new CV claim needs a backing fact and an entry there.
- Every wording rule of the seed needs a case (a claim and an honest text) in `RULE_CASES` of `scripts/unit/cv.test.js`.
