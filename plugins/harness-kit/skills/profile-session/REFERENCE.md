# profile-session reference

How to read a profile and the report, and how the records and files are built. The skill procedure is in
`SKILL.md`, usage in `README.md`, settings in `CONFIGURATION.md`.

## Reading the profile

| Figure | Meaning |
|---|---|
| **Cost units** | `input x 1 + cache read x 0.1 + cache write x 1.25 + output x 5` (the default weights; `costWeights` in the settings changes them, and each record stores the weights it used), over the main thread and every subagent. Relative prices, not money. |
| **Subagent share** | Part of the cost units spent by subagents; it is not in the per-call figures. |
| **Units per call** | Main-thread cost units divided by main-thread calls: the cost of an average call. It grows with the context, and the context with the length of the session, so a long session costs more per call under the same instructions. |
| **First 40 (70) calls, per call** | The same average over only the first 40 (70) main-thread calls; empty for a shorter session. Compare sessions of different length by this and by the length bands of the medians, not by the whole-session figure. |
| **Duration, active / wall** | Wall: from the first human turn to the last main-thread call. Waiting for the user: from the last assistant line to each later human turn, and from an `AskUserQuestion` or `ExitPlanMode` call to its answer. Active = wall − waiting. A permission prompt looks like a long-running tool in the transcript and counts as active. |
| **Calls, human turns, start ctx, max ctx** | Main thread only. A human turn is a message from a person: background-task notifications, compaction summaries and local command output are not. Context = input + cache read + cache write of one call; start ctx is that of the first call (system prompt, instructions and tools before any work). |
| **Cache read, share of cost** | Share of the cost that is re-reading the cached context. Not a hit rate: a short session has few calls to re-read its context, so its share is lower with an equally good cache. |
| **Cache hit** | Cache-read tokens over cache-read plus cache-write tokens. |
| **Idle rebuilds** | Calls after a pause longer than the lifetime of the cache the session writes (one hour or five minutes, read from the transcript; five minutes when the transcript does not say) that wrote over 30k tokens to the cache again. |
| **Compactions** | Calls whose context fell below 60 % of the previous call's (over 50k). |
| **By activity** | Main-thread calls grouped by the tools they used (browser, shell, file reads, edits, build/test, e2e, plan, shipping...); a call with several tools takes the highest-priority one. The Bash and PowerShell tools are read alike (`bash (other)` holds the commands of both that match no rule). The built-in rules know git and `gh`, common build and test commands (`dotnet`, `npm`/`pnpm`/`yarn`, `pytest`, `cargo`, `go`, `mvn`, `gradle`, `make`), browser tools, edits, reads and subagents; a workflow's own tools, agents and skills are named by `activityRules`. A category named only by a rule ranks right after `implement`. |
| **Carrying cost** | Tokens a call added to the context, multiplied by the cache-read weight and the number of later calls that re-read them. Large reads early in a session carry the most. |
| **Rules loaded** | Path-scoped rules pulled in during the session, with a token estimate (characters / 3.76). |
| **Weekly % used, units per 1 %** | Only when the session has two plan-usage readings or more: from the first to the last. |
| **Account** | `org-` and the first four hex digits of the SHA-256 of the `organizationUuid` the transcript records; detected automatically, never entered by hand. Empty for transcripts of Claude Code versions that do not record the field. |

Token totals and context sizes are exact (API usage); the activity split is inferred. The costliest human turns
and the full activity detail are shown on screen only; the record keeps a summary and no per-call data.

**Limits of the weekly-limit figure.** Only the cost between the start and end readings is related to the used
percent: the start reading already contains what the session spent before it, and the end reading nothing after it. Both readings are whole numbers, so
the percent really used is up to one point more or less than the difference; the session breakdown of the report gives the range of units
per 1 % this allows. Other use of the account in the same period (other sessions, chat) counts too. The real limit formula
is not public and may weight models differently, so treat units per 1 % as a trend indicator; 100 x units per 1 %
is only an estimate of the weekly allowance in units for the same plan and model. Used percent and units per 1 %
stay empty when there is no reading or only one, the weekly window rolled over in between (reset times
more than an hour apart), the end is below the start, or no whole percent was used; the start and end readings that
exist are still recorded.

**Account privacy.** Only the four-digit hash prefix is stored or shown; the organization id itself never reaches the
screen, a record or the report. Four digits are enough to tell a handful of accounts apart, not to identify one.

**Comparability.** In the report, the "i" icon next to the work item shows the note of a session and flags a session whose model, Claude Code version or cache lifetime differs from
the previous session in time order, one change per line: a change of cost there may come from that. A cache change is flagged only
when both sessions have a value; the account is shown in its own column and not flagged. The medians table has the
numeric columns of the trend table and one row per lane (Bug or Feature, from the work item's plan file name when `lanePlanGlob` finds one), session
length band and account, plus one over all sessions, and follows the filters of the report; units per 1 % compares like
with like only in the account rows, since each account has its own plan and limit, so a lane, length or all-sessions
row whose limit figures come from more than one account is marked "mixed accounts". `-Marker <label>` is stored with the record as a label and shown as an "M" icon next to the work item; the
report does not group by it. With a handful of sessions the trend is indicative, not statistically reliable.

**Session breakdown.** A click on a trend row or a chart point opens the breakdown of that session in a new browser tab,
the same file with `#session=<id>` and the sort and filters of the table in its address, so several breakdowns can be
compared by switching tabs. Previous / next in that tab step through the trend table as it was filtered and sorted. The
breakdown gives cost and units per call by activity and by subagent type and model (calls and cost split by the model
of each call), carrying cost, rules loaded, context, idle rebuilds, compactions, change size and the limit reading.

**Recomputing the records.** After a change to how the figures are computed, `-Recompute` recomputes the measured
figures of every record whose transcript is still on this machine, over the calls the record first covered, and keeps
what the transcript cannot tell again (work item, lane, branch, commit, author, profile time, note, marker, change size;
the limit figures when the transcript has no plan-usage reading). A record without a transcript, or whose figures did
not change, stays byte-identical; the others are rewritten. Offer to commit the changed records like after a `save`.

**What is in the record.** The work item comes from `-WorkItem`, else from the first of these that holds one under
`workItemPattern`: the branch of the session, the slash command named by `workItemCommandPattern`, a `git commit -m` command
of the session. Claude Code records a branch whose name starts with `#` as `HEAD` in the transcript, so such a branch is
never named there; when the current session is profiled, the checked-out branch and the subject of its last commit stand
in for it. The branch and commit are read from git when the session is profiled, not when it ran.
A workflow that profiles its session before shipping (push, pull request, time report) leaves those last actions out of
the profile. When the record is then amended into the current commit, pass `-NoCommit`: the amend gives that commit a
new id, so the record keeps no commit and the branch names the work.

## Settings

Paths, patterns and cost weights are settings read from three JSON files merged key by key; the layers, every key,
its default and examples are in `CONFIGURATION.md`.

## Files

| File | Purpose |
|---|---|
| `<resultsDir>/records/<yyyy-MM-dd>_<session id>.json` | One summary per saved session (UTC start date, full session id), so saves on parallel branches never touch the same file. `save` refuses a session that has a record. UTF-8 without BOM, LF, two-space indentation and a fixed key order, so the same figures always give the same bytes. |
| `<resultsDir>/report.html` | Self-contained report (data, CSS and JavaScript inline, works offline) rebuilt from all records on every `save`, `-Recompute` and `-Report`; keep it out of git (`.gitignore`). `-NoOpen` skips opening it. |
| `scripts/Profile-Session.ps1` | Entry point; `Get-Help` lists every parameter. |
| `scripts/lib/Session-Profile.ps1` | Transcript parser. |
| `scripts/lib/Cost.ps1` | Cost weights and the cost and token helpers. |
| `scripts/lib/Settings.ps1` | Reads and merges the settings files; finds a work item in a text. |
| `profile-session.config.default.json` | Default settings. |
| `scripts/lib/Session-Report.ps1` | Report builder: embeds the records as JSON in the page template. |
| `scripts/lib/report.html` | Page template of the report: trend table with an info icon per session, filters, paging, medians, chart and how to read it; with `#session=<id>` in the address, the breakdown of that session. |
| `scripts/tests/Test-ProfileSession.ps1` | Checks the parser, the records and the report data on the synthetic session in `scripts/tests/fixtures/session`; run it after changing the scripts. |

Transcripts are read from `<Claude config dir>/projects/<repository key>` (`CLAUDE_CONFIG_DIR`, or `~/.claude`).
Sessions listed in a manifest of `excludeSessionManifests` and SDK sessions are never picked as the newest session.
