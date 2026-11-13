# issue-kit plugin

Takes a GitHub issue, or a batch of small issues, from the issue text to a pull request: read the issue and its
dependencies, plan, review the plan with you, implement with tests, run the build-and-test gate, verify every
acceptance item, commit, comment on the issue, open the pull request and recommend the next issue. Each outward
action (commit, push, comment, pull request) waits for your go-ahead. Claude Code only.

The plugin is installed once per machine and works in every repository. A repository describes its own conventions
(base branch, build commands, issue headings, labels, agents) in one file, `issue-kit.config.json`; see
`CONFIGURATION.md`.

## Contents

| Component | Name | What it does |
|---|---|---|
| Skill | `/issue-kit:implement-issue <n>` | The whole workflow for one issue. You start it; the model does not start it on its own |
| Skill | `/issue-kit:implement-issues <n> <n> …` | Several small issues on one branch, one commit each, one pull request. `--review-plans` keeps the plan review stops, `--ship` pre-authorises push, pull request and comments |
| Skill | `/issue-kit:next-issue` | Recommends the next ready issue from the "blocked by" relations and open pull requests |
| Skill | `/issue-kit:git-commit` | Commit format and branch rules |
| Skill | `/issue-kit:open-pr` | Pull request title, `Closes` lines and description |
| Skill | `/issue-kit:github-issue` | Reads an issue, builds the acceptance list, posts the result comment, ticks the acceptance boxes |
| Skill | `/issue-kit:init-config` | Drafts `issue-kit.config.json` for the repository; `init-config check` validates it |
| Agent | `issue-kit:issue-planner` | Drafts the plan, read-only (Opus) |
| Agent | `issue-kit:issue-developer` | Implements the approved plan with tests (Sonnet; Opus for complexity L) |
| Agent | `issue-kit:build-runner` | Runs the build, tests and format check from the configuration (Haiku) |
| Agent | `issue-kit:skill-runner` | Carries out one approved commit, issue comment or pull request (Haiku) |
| Hook | commit message check | After every `git commit` in the Bash or PowerShell tool, checks the message against `git-commit`. Only in a repository with `issue-kit.config.json` and `commitCheck.enabled` |

Agents and skills that belong to one project (an architect, a security reviewer, a debugging or test-writing skill,
an agent with the project's MCP tools) stay in that repository; the configuration names them in `roles`.

## Requirements

- Claude Code (desktop app or CLI).
- `git`, the GitHub CLI `gh` (signed in, with access to the repository) and PowerShell 7 (`pwsh`) on the path.
- A GitHub repository. Dependencies between issues are GitHub "blocked by" relations.
- Optional: the `harness-kit` plugin, for the session profile at the commit step (see below).

## Install

The marketplace must be registered first: `../../README.md`. Then:

```bash
claude plugin install issue-kit@ai-plugins
```

Start a new session in the repository and run `/issue-kit:init-config`. It drafts `issue-kit.config.json` from the
project files and the repository's labels and issues, shows the draft, writes it after you confirm and prints the
additions for `.claude/settings.json`:

- `enabledPlugins` with `issue-kit@ai-plugins`, so everyone who opens the repository gets the plugin;
- permission rules for the plugin scripts and the `git` and `gh` commands of the workflow, so the agents do not
  stop at a permission prompt;
- `attribution` with empty `commit` and `pr`, because the commit format has no trailers.

Commit `issue-kit.config.json` and the settings change.

## Use it

| Task | Command |
|---|---|
| Take one issue | `/issue-kit:implement-issue 42` |
| Take one issue and stay on the current branch | `/issue-kit:implement-issue 42 stay on current branch` |
| Take a batch | `/issue-kit:implement-issues 5 6 7` (add `--review-plans` or `--ship`) |
| What next? | `/issue-kit:next-issue` |
| Check the configuration | `/issue-kit:init-config check` |

Start each issue in a new session: the workflow keeps its context small and recommends a new session at the end.

Step trees and flowcharts of the two workflows, with every step, gate and agent call:
[implement-issue](docs/implement-issue.md) and [implement-issues](docs/implement-issues.md).

## Session profile (contract with harness-kit)

At the commit step the workflow profiles its own session with the skill named in `profile.skill` (default
`harness-kit:profile-session`). The contract is one-way: issue-kit knows harness-kit, harness-kit knows nothing about
issue-kit.

- If the skill is not available in the session, or `profile.enabled` is `false`, the workflow skips the step with
  one line. Nothing else depends on it.
- The workflow runs the skill in the main session, never in a subagent, and asks you before it saves anything.
- On your yes it passes `save -WorkItem <n> -Lane <lane> -NoCommit`. `<lane>` is `Bug`, `Feature` or
  `Test-authoring`, so `profile-session` needs no `lanePlanGlob` to find the lane. A batch passes the first issue and
  leaves out `-NoCommit`.
- The skill prints `Saved session <id> to <path>.` The workflow takes the record path from that line, not from a
  fixed folder, and adds the record to the commit.

Name the issue-kit agents in the `activityRules` of `profile-session.config.json` with their plugin prefix
(`^Agent:issue-kit:build-runner`); `/issue-kit:init-config` offers matching rules when harness-kit is installed.

## Update

`install` copies the plugin into the plugin cache of your Claude config folder. After a change (your own or a
pull), reinstall and start a new session:

```bash
claude plugin uninstall issue-kit@ai-plugins
claude plugin install issue-kit@ai-plugins
```

## Uninstall

```bash
claude plugin uninstall issue-kit@ai-plugins
```

Remove `issue-kit@ai-plugins` from `enabledPlugins` in the repository's `.claude/settings.json` if you added it
there.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `issue-kit configuration error: … unknown key 'x'` | A typo in `issue-kit.config.json`. The message names the file and the key; `CONFIGURATION.md` lists the keys |
| The commit check does not run | The repository has no `issue-kit.config.json`, or `commitCheck.enabled` is `false` |
| The commit check reports a title mismatch | Line 1 must be `#<n> <exact issue title>` on every commit of the branch; amend the commit before the push |
| `build-runner` reports `NOT CONFIGURED` | Set `commands.build`, `commands.testFull` and `commands.format` in `issue-kit.config.json` |
| An agent stops at a permission prompt | Add the permission rules that `/issue-kit:init-config` prints to `.claude/settings.json` |
| An agent of `roles` is not found | Plugin agents need the prefix (`issue-kit:build-runner`); repository agents have none (`architect`). Run `/issue-kit:init-config check` |
| The session profile step is skipped | harness-kit is not installed or not enabled; `claude plugin list` |
| `pwsh: command not found` | Install PowerShell 7 and make sure `pwsh` is on the path of the shell Claude Code uses |
