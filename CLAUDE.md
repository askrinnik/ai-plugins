# ai-plugins repository

A Claude Code plugin marketplace. `README.md` describes the layout and how to register and install plugins.

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

## Writing style

Write skills and instructions by the rules of ASD-STE100 Simplified Technical English: its writing rules, not its
dictionary.

- Start with the conclusion or answer. Then add the details.
- Use the imperative. Write one instruction per sentence.
- Put the condition before the action: "If X, do Y".
- Use one term for one concept.
