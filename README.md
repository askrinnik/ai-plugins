# ai-plugins

A Claude Code plugin marketplace: a repository with `.claude-plugin/marketplace.json` that lists the plugins
kept in `plugins/`. Nothing is published to a public catalog; the marketplace is read from a clone of this repository
or straight from GitHub.

## Plugins

| Plugin | What it is | Documentation |
|---|---|---|
| `harness-kit` | Tools that measure and check the Claude Code harness of any repository; skill `profile-session` profiles finished work sessions | `plugins/harness-kit/README.md` |
| `jobsearch-kit` | Job search workflow: vacancy analysis, tailored CVs, cover letters, application records, call transcripts | `plugins/jobsearch-kit/README.md` |

## Requirements

Claude Code (desktop app or CLI) and `git`. Each plugin lists its own further requirements in its README.

## Register the marketplace, once per machine

Choose one source. Run the command in any terminal.

| Source | Command | Notes |
|---|---|---|
| Local clone | `claude plugin marketplace add <path to the clone>` | Changes in the clone are read in place. Keep the clone where it is: the marketplace is read from that path |
| GitHub | `claude plugin marketplace add askrinnik/ai-plugins` | Refresh with `claude plugin marketplace update ai-plugins` |

The marketplace name is `ai-plugins`. If another marketplace with that name is already registered, Claude Code does
not add this one. Uninstall the plugins of the other marketplace, remove it with
`claude plugin marketplace remove ai-plugins`, then add this one.

| Task | Command |
|---|---|
| List registered marketplaces | `claude plugin marketplace list` |
| Remove the marketplace | `claude plugin marketplace remove ai-plugins` (uninstall its plugins first) |
| The clone moved | Remove the marketplace as above and add it again from the new path |

## Install, update and remove a plugin

| Task | Command |
|---|---|
| Install | `claude plugin install <plugin>@ai-plugins`, then start a new session |
| List installed plugins | `claude plugin list` |
| Update after a change | `claude plugin uninstall <plugin>@ai-plugins`, then `claude plugin install <plugin>@ai-plugins`, then start a new session |
| Remove | `claude plugin uninstall <plugin>@ai-plugins` |

`install` copies the plugin into the plugin cache of the Claude config folder, and sessions run that copy. A change
in the clone therefore reaches a session only after a new install. Each plugin README gives the details.
