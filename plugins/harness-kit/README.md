# harness-kit plugin

Tools that measure and check the Claude Code harness of the repository you are in: its instructions, rules, skills,
agents and workflows. Each skill is invoked by its own name or in the long form `/harness-kit:<skill>`. The plugin
is installed once per machine for your user and then works in every repository; nothing is copied into a repository
except an optional settings file of a skill.

## Skills

| Skill | What it does | Documentation |
|---|---|---|
| `profile-session` | Profiles finished work sessions: calls, weighted cost, estimated cost in USD at API list prices, context growth, cache behaviour, cost by activity, share of the weekly plan limit; keeps one record per session and builds a local report | `skills/profile-session/README.md` |
| `harness-quality-check` | Runs fixed test sessions (fixtures kept in the repository under test) and records context size, rules loaded, cost and judged answer quality; compares each run with the previous one. Started by you only | `skills/harness-quality-check/README.md` |

## Contract with workflow plugins

`profile-session` can be called by the workflow of another plugin, for example the `issue-kit` workflow of this
marketplace at its commit step. The dependency is one-way and optional: harness-kit has no code or setting that knows
the caller, and the caller skips its profile step when harness-kit is not installed. The caller passes
`save -WorkItem <id> -Lane <lane> -NoCommit` and takes the record path from the line `Saved session <id> to <path>.`
that the script prints. Details: `skills/profile-session/README.md`, section "Called by a workflow plugin".

## Requirements

Claude Code (desktop app or CLI), `git` and PowerShell 7 (`pwsh`) on the path. Each skill lists anything further in
its own README.

## Install

The marketplace must be registered first: `../../README.md`. Then, in any terminal:

```bash
claude plugin install harness-kit@ai-plugins
```

This installs for your user (`--scope user`, the default). Use `--scope project` only if a repository should declare
the plugin for everyone who opens it; the marketplace clone path must then exist for each of them. Check with
`claude plugin list`: `harness-kit@ai-plugins` must be enabled. Start a new session to use it.

## Update

`install` copies the plugin into the plugin cache of your Claude config folder
(`plugins/cache/ai-plugins/harness-kit/<version>/`), and the desktop app runs that copy. `claude plugin update`
reports a directory marketplace as read in place and copies nothing, so a change to this folder does not reach the
copy by itself. After a change (your own or a pull):

```bash
claude plugin uninstall harness-kit@ai-plugins
claude plugin install harness-kit@ai-plugins
```

then start a new session. A new install copies the folder afresh even at the same version; raise `version` in
`.claude-plugin/plugin.json` when the change is worth telling apart. To check which copy a session runs, look at the
skill's base directory shown when the skill loads: it ends in the version of `plugin.json`.

## Uninstall

```bash
claude plugin uninstall harness-kit@ai-plugins
```

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| A skill command is not found | The plugin is not enabled in this session: `claude plugin list`, then a new session |
| Plugin changes do not appear | The session runs the installed copy in the plugin cache: update as above, then start a new session |
| `pwsh: command not found` | Install PowerShell 7 and make sure `pwsh` is on the path of the shell Claude Code uses |

Problems with a single skill are in that skill's README.

## Development

Skills live in `skills/<name>/`, each with its own `README.md` for people and `SKILL.md` for the model. Run a skill's
tests after changing its scripts:

- `profile-session`: `pwsh skills/profile-session/scripts/tests/Test-ProfileSession.ps1`;
- `harness-quality-check`: `pwsh ../../tests/harness-kit/HarnessQualityCheck.Cases.ps1` (a dry run in a temporary
  repository; it starts no session).

To update the default model prices of `profile-session` from the Anthropic pricing page, run from the repository
root of a clone, not from the plugin cache:

```bash
pwsh plugins/harness-kit/skills/profile-session/scripts/Profile-Session.ps1 -Refresh -Target Defaults
pwsh plugins/harness-kit/skills/profile-session/scripts/Profile-Session.ps1 -Refresh -Target Defaults -Apply
```

The first command shows the differences; the second writes them to `profile-session.config.default.json`. Then
raise `version` in `.claude-plugin/plugin.json` and commit. Users get the new prices after they reinstall the
plugin.
