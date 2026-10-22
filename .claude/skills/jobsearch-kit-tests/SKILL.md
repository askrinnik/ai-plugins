---
name: jobsearch-kit-tests
description: Run the jobsearch-kit developer tests (script tests and skill fixtures in headless sessions) and report the results in plain words. Use when the developer asks to test jobsearch-kit, run a fixture, check a plugin change for regressions, or explain a test report.
---

# Run the jobsearch-kit tests

The tests and their format are described in `tests/jobsearch-kit/README.md`. Read it before the first run in a
session. Run every command from the repository root.

## Choose what to run

1. If a script or the workspace template changed, run the script tests first. They are free and take seconds:
   `pwsh -File tests/jobsearch-kit/scripts/Test-Scripts.ps1`. Add `-SkipWord` if the developer is in a hurry.
2. If a skill changed, pick the fixtures of that skill (`tests/jobsearch-kit/fixtures/`, the table in the README).
   If nothing is named, ask which fixtures to run.
3. Show the plan before a skill test run: `pwsh -File tests/jobsearch-kit/scripts/Run-Tests.ps1 -Fixture <names> -DryRun`.
   Tell the developer the number of sessions and the expected time, and that the sessions use the Claude usage limit.
   Start the run only after a yes, unless the developer already asked to run these fixtures.

## Run

- Run `Run-Tests.ps1 -Fixture <names> -Note "<what changed>"`. Write the note from the change under test, in a few
  words. Run it in the background if it may take more than two minutes.
- Use 1 repetition during development (`-Repetitions 1`). Use the fixture's own repetitions only for the final check
  before a commit.
- Never run a fixture marked `slow` without the developer's explicit request.

## Report

Read `tests/jobsearch-kit/reports/<run id>.md` and tell the developer:

- The result in one sentence: how many repetitions passed, and whether any fixture shows `REGRESSION`.
- For each failed repetition: which turn, which check, expected and actual, in plain words; the judge's reasons from
  `tests/jobsearch-kit/runs/<run id>/<fixture>/r<n>/judge-<turn>.md` for a low score; the kept workspace path.
- Permission denials: name the denied tools (`deniedTools` in `result.json`) and suggest adding them to the fixture's
  tools if the skill needs them.
- Time and cost of the run.

Do not change a fixture, a check or a ground truth to make a failing run pass unless the developer agrees that the
expectation was wrong. Say whether the failure looks like a skill problem, a fixture problem or model noise, and why.

Remind the developer to commit `tests/jobsearch-kit/run-history.csv` and the new report with the change they checked.
