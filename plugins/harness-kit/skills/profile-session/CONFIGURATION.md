# Configuring profile-session

The skill works without any settings file: the defaults in `profile-session.config.default.json` (next to this file)
describe a repository that keeps plans in `.ai/plans/`, names work items `#<id>` and writes results to
`.ai/benchmarks/sessions/`. Everything else is a setting.

## Where settings live

Three JSON files, merged key by key; a later file overrides the earlier one:

| Layer | File | Use it for |
|---|---|---|
| 1. defaults | `profile-session.config.default.json` in the skill folder | Never edit; copy a key into layer 2 or 3 |
| 2. user | `profile-session.config.json` in the Claude config folder (`~/.claude/`, or `CLAUDE_CONFIG_DIR`) | Values for all of your repositories, for example `costWeights` |
| 3. repository | `profile-session.config.json` in the repository root | Values that describe this repository's branches, tools and folders |

Every key is optional and a missing file is not an error. An unknown key, a value of the wrong type or an invalid
regular expression stops the run with a message that names the file and the key. A list replaces the list of the
earlier layer as a whole; `costWeights` merge weight by weight. The repository file is the one to commit; it is read
from the repository root, never from the results folder, so `resultsDir` cannot point at its own settings.

## Keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `resultsDir` | text | `.ai/benchmarks/sessions` | Folder with `records/` (one JSON file per saved session) and `report.html`. Relative to the repository root, or absolute. |
| `baseBranch` | text | empty | Branch the change size (files and lines changed) is measured against. Empty: the branch `origin/HEAD` points to, else the first of `develop`, `main`, `master` that exists, else no change size. |
| `workItemPattern` | text or list | `^#(\d+)` | Regular expression(s), tried in order, matched against the branch name and against the first line of each `git commit -m` message of the session. The first capture group is the work item; without a group, the whole match. No match: the work item stays empty. |
| `workItemCommandPattern` | text | empty | Regular expression naming a slash command whose first argument is the work item, for example `/implement-work-item`. Empty: commands are not read. |
| `lanePlanGlob` | text | `.ai/plans/*-{id}-*.md` | Plan file of a work item, relative to the repository root, `{id}` replaced by the work item. A file name starting with `bug-` gives lane Bug, any other name Feature. Empty, or no file: no lane. |
| `excludeSessionManifests` | list | empty | Folders of `*_manifest.json` files whose `sessions[].session` ids are never picked as the newest session (for example the test sessions of a benchmark). |
| `activityRules` | list | empty | `[{ "pattern": "<regex>", "category": "<name>" }]`, tried in order before the built-in rules. The pattern is matched against each tag of a call (see below). |
| `costWeights` | object | 1, 0.1, 1.25, 5 | `input`, `cacheRead`, `cacheWrite`, `output`: relative price of one token of each kind. Each record stores the weights it was costed with; sessions costed with different weights are not comparable in cost units, and the report says so. |

### Activity rules

Each model call is classified by the tools it used. A tag is built per tool use: `Read`, `Edit:<path>`,
`Write:<path>`, `Bash:<command>` (for the Bash and the PowerShell tool alike), `Agent:<subagent type>`, `Skill:<name>`, or the tool name for any other tool
(`mcp__server__tool`). The first rule, the settings' rules before the built-in ones, whose pattern matches a tag gives
that tag its category; a call with several tags takes the highest-priority category:

`ship` > `e2e` > `build/test` > `implement` > (categories named only by your rules) > `browser verify` > `plan` >
`other subagent` > `skill load` > `ado read` > `explore (read/search)` > `bash (other)` > `other tool`

A call with no tool is `reply (no tools)`. `bash (other)` holds the commands of the Bash and the PowerShell tool that match no rule. Use the built-in names above so that sessions of different repositories
group alike; any other name is allowed. The built-in rules cover git and `gh`, `dotnet`, `npm`/`pnpm`/`yarn`
`test|build|lint`, `pytest`, `cargo`, `go`, `mvn`, `gradle`, `make`, Playwright and Cypress, edits, reads and browser
tools. To keep a rule from claiming a commit, use a negative lookahead:
`^Bash:(?!.*git (commit|push)).*E2ETests`.

## Examples

### Example 1: Azure DevOps work items

Branches `#<id>`, a `/implement-work-item` command, plans in `.ai/plans/`, Azure DevOps tools, `develop` as the
integration branch.

```json
{
  "baseBranch": "develop",
  "workItemCommandPattern": "/implement-work-item",
  "excludeSessionManifests": [".ai/benchmarks/harness/runs"],
  "activityRules": [
    { "pattern": "^Agent:skill-runner|^Skill:(git-commit|pull-request|post-rca|release|report-time)", "category": "ship" },
    { "pattern": "AzureDevOps__.*(_write|comment_write|update|create)|repo_pull_request", "category": "ship" },
    { "pattern": "^Bash:(?!.*git (commit|push|switch -c|checkout -b)).*(npm (test|run)|npx playwright|E2ETests)", "category": "e2e" },
    { "pattern": "^Agent:wi-developer|^Agent:software-engineer", "category": "implement" },
    { "pattern": "^Write:.*\\.ai.plans|^Agent:wi-planner", "category": "plan" },
    { "pattern": "AzureDevOps__", "category": "ado read" }
  ]
}
```

### Example 2: GitHub issues

Branches `<issue>-<slug>` (a batch branch such as `54-57-fix` gives its first issue), commits `#<issue> <title>`,
`/implement-issue` and `/implement-issues` commands, base branch `main` (found without a setting), no plan files, so
no lane. `gh` is already a built-in `ship` rule.

```json
{
  "workItemPattern": ["^(\\d+)-", "^#(\\d+)"],
  "workItemCommandPattern": "/implement-issues?",
  "lanePlanGlob": "",
  "excludeSessionManifests": [".ai/benchmarks/harness/runs"],
  "activityRules": [
    { "pattern": "^Agent:skill-runner|^Skill:(git-commit|open-pr|github-issue)", "category": "ship" },
    { "pattern": "^Agent:issue-developer", "category": "implement" },
    { "pattern": "^Agent:issue-planner", "category": "plan" }
  ]
}
```

### Example 3: GitHub issues with API and UI test suites

As above, plus the Playwright suites under `src/ApiTests` and `src/UiTests`, which run through `dotnet test` and are
`e2e` rather than `build/test`, and a `build-runner` agent.

```json
{
  "workItemPattern": ["^(\\d+)-", "^#(\\d+)"],
  "workItemCommandPattern": "/implement-issues?",
  "lanePlanGlob": "",
  "excludeSessionManifests": [".ai/benchmarks/harness/runs"],
  "activityRules": [
    { "pattern": "^Agent:skill-runner|^Skill:(git-commit|open-pr|github-issue)", "category": "ship" },
    { "pattern": "^Bash:(?!.*git (commit|push)).*(ApiTests|UiTests)", "category": "e2e" },
    { "pattern": "^Agent:build-runner", "category": "build/test" },
    { "pattern": "^Agent:issue-developer", "category": "implement" },
    { "pattern": "^Agent:issue-planner", "category": "plan" }
  ]
}
```

### Example 4: another stack, no conventions

A Python or Node repository that names branches `feature/PROJ-123-title` and has no plan files needs only the work
item pattern; the built-in rules already recognise `pytest` and `npm test`:

```json
{
  "workItemPattern": ["(?:^|/)([A-Z][A-Z0-9]+-\\d+)"],
  "lanePlanGlob": ""
}
```

## Checking a configuration

Run the profiler on a finished session without `save` (nothing is written) and read the first lines:

```powershell
pwsh "<skill folder>/scripts/Profile-Session.ps1"
```

`Work item`, `lane`, `branch` and `commit` show what the patterns found, and the `By activity` block shows how the
calls were classified; a large `bash (other)` or `other tool` share points at commands or tools that need a rule.
