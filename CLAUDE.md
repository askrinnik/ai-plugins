# ai-plugins repository

A Claude Code plugin marketplace. `README.md` is for the people who use the plugins: what the marketplace lists and
how to register it and install, update and remove a plugin. This file is for the people who develop the plugins.

## Rules

- Write all repository text in English: code, comments, documentation, skills, commit messages, issue and PR text.
- Keep personal data out of the repository. Plugins hold logic, procedures and templates; each user's data stays in
  that user's own workspace. Do not write personal names, absolute paths of a particular machine, employers,
  companies or people from a user's workspace. In the `author` and `owner` fields use the GitHub account name
  `askrinnik`.
- Use fictional data in templates, examples and test fixtures.
- If a plugin changes, raise its `version` in `.claude-plugin/plugin.json`.
- If a plugin is added, removed or renamed, update `.claude-plugin/marketplace.json` and the table in `README.md`.
- Run `claude plugin validate .` in the repository root before a commit that changes a plugin or the marketplace.
- If several skills of a plugin use one script, keep it in `plugins/<name>/scripts/`. Do not copy scripts between
  skills.
- Keep developer instructions out of `README.md` files: they are for users.

## Add a plugin

1. Create `plugins/<name>/` with `.claude-plugin/plugin.json` (`name`, `description`, `version`, `author`).
2. Put the plugin's skills under `plugins/<name>/skills/<skill>/SKILL.md`. Put scripts that several skills share
   under `plugins/<name>/scripts/`; a skill calls them as `${CLAUDE_SKILL_DIR}/../../scripts/<script>`.
3. Write `plugins/<name>/README.md`: what the plugin does, requirements, install, update, removal, troubleshooting.
4. Add an entry to `plugins` in `.claude-plugin/marketplace.json` with `name`, `source` (`./plugins/<name>`) and
   `description`.
5. Add the plugin to the table in `README.md`.
6. Run `claude plugin validate .` in the repository root.

## Documentation levels

| Level | Folder | README answers |
|---|---|---|
| Marketplace | repository root | What it lists, how to register it, how to install, update and remove a plugin |
| Plugin | `plugins/<name>/` | What it contains, requirements, how to install, update, remove and troubleshoot it |
| Skill | `plugins/<name>/skills/<skill>/` | What it does and how to use it (optional; `SKILL.md` is enough for small skills) |

## Test a change

- `tests/<plugin>/` holds the developer tests of a plugin and their materials (fictional inputs, reference outputs).
  It is outside `plugins/`, so it is not installed with the plugin.

- To try a plugin from the clone without installing it, start the CLI with `claude --plugin-dir plugins/<plugin>`
  from a test workspace.
- For a plugin that is installed, reinstall it after a change (`claude plugin uninstall`, then
  `claude plugin install`) and start a new session.

## Writing style

Write skills and instructions by the rules of ASD-STE100 Simplified Technical English: its writing rules, not its
dictionary.

- Start with the conclusion or answer. Then add the details.
- Use the imperative. Write one instruction per sentence.
- Put the condition before the action: "If X, do Y".
- Use one term for one concept.
