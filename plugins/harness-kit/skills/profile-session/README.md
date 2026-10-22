# profile-session

Profiles finished Claude Code work sessions of the repository you are in: model calls, weighted cost, context growth,
cache behaviour, cost by activity and the share of the weekly plan limit used. `save` keeps one small JSON record per
session and builds a local, self-contained `report.html` with the trend, medians and a breakdown per session. It works
in any repository, whatever its language or workflow.

| File | For |
|---|---|
| `README.md` | This file: using the skill in a repository |
| `CONFIGURATION.md` | Every setting, its default, and example configurations |
| `REFERENCE.md` | How to read the figures and the report, what a record holds, the file list |
| `SKILL.md` | Instructions the model follows when the skill runs; not meant for reading |

Installing the plugin: `../../README.md`.

## Requirements

- Claude Code (desktop app or CLI). The weekly-limit columns need the desktop app's `get_usage` tool; without it they
  stay empty and everything else works.
- `git` and PowerShell 7 (`pwsh`) on the path. The scripts run on Windows, macOS and Linux.

## Prepare a repository

1. Add the report to `.gitignore`. The default location is `.ai/benchmarks/sessions/report.html`; use your
   `resultsDir` if you change it.
2. Decide whether the records (`<resultsDir>/records/*.json`, one small file per saved session) are committed. They
   are plain summaries without per-call data; the only trace of the account is `account`, the first four hex digits of
   a hash of the organization id. Committing them gives the repository a history of what its sessions cost, and
   parallel branches never touch the same file.
3. Optional: add `profile-session.config.json` in the repository root so the skill recognises the repository's work
   item format, base branch and tools. Without it the defaults apply (work item `#<id>` at the start of a commit
   subject, plans in `.ai/plans/`, base branch detected). Copy the closest example from `CONFIGURATION.md`.
4. Check the configuration on a finished session, which writes nothing:

   ```text
   /profile-session <session id or 8-character prefix>
   ```

   Read `Work item`, `lane`, `branch` and the `By activity` block. A large `bash (other)` or `other tool` share means
   commands or tools that need an `activityRules` entry (`bash (other)` also holds the commands of the PowerShell
   tool that match no rule).

## Use it

The skill is `/profile-session`; the long form is `/harness-kit:profile-session`.

| When | Command | Result |
|---|---|---|
| At the start of a session whose cost should be related to the weekly limit | `/profile-session start` | Takes the start reading of the plan usage; writes nothing |
| At the end of any session | `/profile-session` | Shows the profile of the current session; writes nothing tracked |
| Same, and keep it | `/profile-session save` | Writes one record, rebuilds `report.html` and opens it; commit the record yourself, the skill only offers |
| Another finished session | `/profile-session <id or prefix>` (add `save` to keep it) | The same for that session |
| Only the report | `/profile-session report` | Rebuilds and opens `report.html` from the records |

`-WorkItem`, `-Note`, `-Marker` and `-NoCommit` can be added to a `save`. `/clear` starts a new transcript, so take
the start reading again after it. To check the scripts after changing them:
`pwsh scripts/tests/Test-ProfileSession.ps1`.

## What stays empty without matching settings

| Column | Empty when |
|---|---|
| Work item | no pattern in `workItemPattern` matches the branch, a commit subject or the command of the session |
| Lane | the work item has no plan file found by `lanePlanGlob` |
| Change size | no base branch is found and `baseBranch` is empty |
| Weekly % used, units per 1 % | the session has fewer than two `get_usage` readings (CLI, or no `start`), or the weekly window rolled over |
| Account | the transcript does not record an organization (older Claude Code) |

## A repository with its own workflow command

The skill never changes a workflow. A command of that repository that should relate its sessions to the plan limit
adds two lines of its own: call the `get_usage` tool at its first step, and run `/profile-session` (show, then offer
`save`) in the main session, not in a subagent: a subagent has its own transcript. Profiling after the work is committed
and before the push lets the record travel in that commit: save with `-NoCommit` and amend the commit while it is not
pushed yet, or add a new commit when it is. The steps after the profile (push, pull request) are not part of it.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `pwsh: command not found` | Install PowerShell 7 and make sure `pwsh` is on the path of the shell Claude Code uses |
| `No transcript folder at …` | Claude Code has not recorded a session for this folder yet, or `CLAUDE_CONFIG_DIR` points elsewhere in this terminal |
| The wrong session is profiled | Pass the id explicitly: `/profile-session <id or prefix>` |
| `<file> : unknown setting '…'` | A typo in a settings file; the message names the file and the key |
| Figures differ after a settings change | Cost weights are stored in each record; a session costed with other weights is flagged in the report and is not comparable in cost units |

Problems with the command itself (not found, old behaviour after a change) are plugin problems: `../../README.md`.
