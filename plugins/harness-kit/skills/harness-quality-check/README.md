# harness-quality-check

Measures what the assistant harness of a repository costs and whether it still works: `CLAUDE.md`, `.claude/rules/`,
skills, agents, memory, MCP servers and settings. It runs fixed test sessions ("fixtures") against the current state
of the repository, records the same metrics for every session (context at the first and the last model call, calls,
output tokens, weighted cost, rules loaded) and, for fixtures with a ground truth, a score from an LLM judge. Each run
appends to a history and writes a report that compares every fixture with its previous run.

| File | For |
|---|---|
| `README.md` | This file: preparing a repository and using the skill |
| `SKILL.md` | Instructions the model follows, with the metrics, comparability rules and the file list |

Installing the plugin: `../../README.md`.

## Requirements

- Claude Code CLI (`claude`) on the path: the skill starts real `claude -p` sessions, which use a part of the usage
  limit.
- `git` and PowerShell 7 (`pwsh`).

## Prepare a repository

The skill comes from the plugin; the fixtures, the history, the runs and the reports stay in the repository under
test, in the benchmark folder `.ai/benchmarks/harness/`.

1. Add a fixture: a folder `.ai/benchmarks/harness/fixtures/<name>/` with a `prompt.txt`. Start with a `bench-base`
   fixture whose prompt only asks for a short reply: it measures what the repository loads at the start of a session.
   `SKILL.md` (section *Files*) lists the optional files: `fixture.json`, `seed.patch`, `ground-truth.md`.
2. To keep the benchmark folder elsewhere, add `harness-quality-check.config.json` in the repository root:

   ```json
   { "dir": "tools/bench" }
   ```

   The path is relative to the repository root. Any other key is an error.
3. If the repository uses `profile-session`, add the runs folder to its `excludeSessionManifests`
   (`.ai/benchmarks/harness/runs`), so that the test sessions are never profiled as work sessions.
4. Check the setup without starting a session, from the repository root:

   ```bash
   pwsh "<plugin folder>/skills/harness-quality-check/scripts/Run-Harness.ps1" -DryRun
   ```

## Use it

The skill is started by you only: `/harness-kit:harness-quality-check [fixture or mask ...] "<what changed>"`, for
example after a change to `CLAUDE.md`, the rules, skills or agents, or after a Claude Code update. Commit the history,
the runs and the report with the change they measured; the skill offers it and waits for your go-ahead.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `not inside a git repository` | Start the session in the repository under test; the scripts never measure the plugin folder |
| `No fixtures with a prompt.txt` | The benchmark folder has no fixture yet, or `dir` points elsewhere |
| `seed.patch does not apply` | A previous run was interrupted while the patch was applied (`git apply -R <patch>`), or the patched code changed and the fixture needs an update |
| `Nothing was written to the history` | A session could not be parsed or judged; fix the cause and run `Collect-Harness.ps1 -Run <RunId>` again |
