---
name: profile-session
description: 'Profile a finished Claude Code work session of the current repository (main thread plus subagents): model calls, human turns, weighted cost, cost per call, context growth, cache-read share, idle cache rebuilds, compactions, cost by activity, carrying cost of large reads, rules loaded, and the share of the weekly plan limit used between the plan-usage readings of the session. Shows the profile on screen; with `save` writes one JSON record per session to the results folder (default .ai/benchmarks/sessions/records/) and rebuilds a local HTML report of all records (sortable, filterable, with medians, a chart and a breakdown per session); `report` only rebuilds and opens that report. `start` only takes the start reading of the plan limit. Use when the user asks what a session cost or how real sessions trend, at the start of a session whose cost should be related to the plan limit, and at the end of a work-item workflow that profiles its own sessions. Claude Code only.'
argument-hint: '[start] | [report] | [session id or 8-char prefix] [save] [-WorkItem id] [-Note text] [-Marker text] [-NoCommit]'
---

# profile-session

Every model call re-reads the whole context, so the cost of a work session is roughly its number of calls times
its context size. This skill measures that on a real, finished session from its transcript and keeps one summary
record per session, so the effect of changes to the instructions, the workflow or the model shows up in the trend. It measures
real sessions; a benchmark that runs fixed test sessions is repeatable, this is not, so compare sessions of similar size.
It works in any repository: paths, patterns and cost weights are settings (see `CONFIGURATION.md`).

## Procedure

1. Read the arguments. `start` means: call `get_usage` (the plan-usage tool of the Claude desktop app) in this
   session, tell the user in one line that the start reading is taken, and stop; nothing else runs and no file is
   written. Without the tool, say that the host does not expose plan usage. `report` means: run the profiler with
   `-Report`, which rebuilds `report.html` from the records and opens it, and stop. Otherwise a session id or prefix selects
   that session; without one the current session is profiled (see step 3). The word `save` records the profile; without it nothing tracked is written.
   Pass `-WorkItem`, `-Note`, `-Marker` and `-NoCommit` through as given.
2. When profiling the current session and the host exposes `get_usage`, call it first: that result is the end
   reading of the weekly limit.
3. Run the profiler in this session, not in a subagent (a subagent has its own transcript and its `get_usage`
   results are not read). The current session is passed by its id, so the right transcript is found even when
   other sessions of the repository are newer. Without `save` omit `-Save`; for another session put its id or
   prefix first and leave out `-CurrentSession`:

   ```powershell
   pwsh "${CLAUDE_SKILL_DIR}/scripts/Profile-Session.ps1" -CurrentSession "${CLAUDE_SESSION_ID}" [-Save] [-WorkItem <id>] [-Note "<text>"] [-Marker "<label>"] [-NoCommit]
   pwsh "${CLAUDE_SKILL_DIR}/scripts/Profile-Session.ps1" <session id or prefix> [-Save] [-WorkItem <id>]
   pwsh "${CLAUDE_SKILL_DIR}/scripts/Profile-Session.ps1" -Report
   ```
4. Show the profile to the user in plain words: calls, cost units and units per call, the largest activities, the
   costliest turns, idle rebuilds and compactions, and the weekly-limit figure if there is one. Do not paste the
   whole output when a summary will do.
5. After a `save`, the new record `<resultsDir>/records/<yyyy-MM-dd>_<session id>.json` is the only new
   tracked file; the script also rebuilds `report.html` (not tracked) and opens it in the default browser. Do not
   commit the record on your own: offer to, on the current branch, and wait for the go-ahead.

**Plan-limit readings.** The result of every `get_usage` call on the main thread is written to the session
transcript with its time; the profiler reads them from there. The first one is the start reading and the last one
the end, so a session that should be related to the plan limit needs one call near its start (`/profile-session
start`, or the first step of a workflow that does it) and one at the end, which this skill makes itself. Readings in between
do no harm. `/clear` starts a new transcript, so take the start reading again after it.

For the meaning of every figure, the limits of the weekly-limit figure, what a record holds and the file list, read
`REFERENCE.md` in this folder; settings are in `CONFIGURATION.md`.
