# ai-plugins

A personal Claude Code plugin marketplace: a repository with `.claude-plugin/marketplace.json` that lists the plugins
kept in `plugins/`. Nothing is published to a public catalog; the marketplace is read from a clone of this repository
or straight from GitHub.

## Plugins

| Plugin | What it is | Documentation |
|---|---|---|

## Requirements

Claude Code (desktop app or CLI) and `git`. Each plugin lists its own further requirements in its README.

## Register the marketplace, once per machine

Choose one source. Run the command in any terminal.

| Source | Command | Notes |
|---|---|---|
| Local clone | `claude plugin marketplace add <path to the clone>` | Changes in the clone are read in place. Keep the clone where it is: the marketplace is read from that path |
| GitHub | `claude plugin marketplace add askrinnik/ai-plugins` | The repository is private: `git` on the machine must have access to it. Refresh with `claude plugin marketplace update ai-plugins` |

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

To try a plugin from the clone without installing it, start the CLI with `claude --plugin-dir plugins/<plugin>`.

## Add a plugin

1. Create `plugins/<name>/` with `.claude-plugin/plugin.json` (`name`, `description`, `version`, `author`).
2. Put the plugin's skills under `plugins/<name>/skills/<skill>/SKILL.md`. Put scripts that several skills share
   under `plugins/<name>/scripts/`; a skill calls them as `${CLAUDE_SKILL_DIR}/../../scripts/<script>`.
3. Write `plugins/<name>/README.md`: what the plugin does, requirements, install, update, removal, troubleshooting.
4. Add an entry to `plugins` in `.claude-plugin/marketplace.json` with `name`, `source` (`./plugins/<name>`) and
   `description`.
5. Add the plugin to the table above.
6. Run `claude plugin validate .` in the repository root.

## Layout and documentation

| Level | Folder | README answers |
|---|---|---|
| Marketplace | repository root | What it lists, how to register it |
| Plugin | `plugins/<name>/` | What it contains, how to install, update, remove and maintain it |
| Skill | `plugins/<name>/skills/<skill>/` | What it does and how to use it (optional; `SKILL.md` is enough for small skills) |
