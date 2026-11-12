# issue-kit developer tests

Script tests of the issue-kit plugin. They start no model session and make no GitHub call; all data is fictional.

Run all of them from the repository root:

```bash
pwsh -NoProfile -File tests/issue-kit/Test-IssueKit.ps1
```

| File | What it checks |
|---|---|
| `Config.Cases.ps1` | The configuration reader: defaults, the merge of the three layers, and that every invalid value stops with a message that names the file and the key |
| `Scripts.Cases.ps1` | `Set-AcceptanceChecks.ps1` on a sample issue body (`-BodyFile`) and the order of `Get-NextIssue.ps1` on sample issues (`-IssuesFile`) |
| `CommitMessageRules.Cases.ps1` | The commit message rules of the hook, with the default and with configured branch patterns |
| `Check.Cases.ps1` | The configuration check of `init-config check` in a temporary repository: paths, commands, agents and skills of `roles`, base branch |
| `Hook.Cases.ps1` | The hook in temporary git repositories: it does nothing without `issue-kit.config.json` or with `commitCheck.enabled` false, and blocks a bad message otherwise |
| `materials/` | Sample issue body and GraphQL issue nodes |

To try the skills and agents themselves, start the CLI with `claude --plugin-dir plugins/issue-kit` in a clone of a
test repository, outside this repository.
