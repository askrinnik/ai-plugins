---
name: git-commit
description: 'Create Git commits by the issue-kit branch and commit-message conventions of the current repository. Use when the user asks to commit, make a commit or write a commit message, and for the commit step of /issue-kit:implement-issue and /issue-kit:implement-issues. Chooses the format by whether the work belongs to a GitHub issue. Covers committing only; pull requests are in the open-pr skill.'
argument-hint: 'Optional: issue number, or leave empty for a commit not tied to an issue'
---

# git-commit

Use this skill for every commit in a repository that uses issue-kit. It covers commit mechanics only, not pull
requests.

Commit only when the user asks, or when a calling workflow already holds the user's go-ahead. Never push unless the
user asks.

## Read the configuration

Run once, from the repository root:

```bash
pwsh -NoProfile -File "${CLAUDE_SKILL_DIR}/../../scripts/Get-IssueKitConfig.ps1"
```

Use `baseBranch`, `branchPattern`, `batchBranchPattern`, `shipLanguage` and `plans` from the output. If the script
reports a configuration error, stop and show the message: it names the file and the key.

## Choose the branch first

Work for issue `<n>` happens on the branch that `branchPattern` gives, for example `42-add-export` for `{n}-{slug}`.
`{slug}` is a short kebab-case slug of the English issue title.

- Issue work never goes to `baseBranch`. A commit on `baseBranch` is work not tied to an issue and always uses
  Case 2.
- Run `git branch --show-current`. If the current branch is the branch of issue `<n>`, commit there.
- Run `git branch --list` with the pattern of issue `<n>`. If that branch exists but is not checked out, switch to it.
- If you are on `baseBranch` and the commit belongs to an issue, create the branch from an up-to-date `baseBranch`:
  run `git pull --ff-only` first, then `git switch -c <branch>`. If the pull fails (diverged history or local
  conflicts), stop and report it. Uncommitted changes travel with you. Ask the user first, unless a calling workflow
  already decided it.

## Commit message

Write all commit text in `shipLanguage`.

### Case 1: the commit belongs to an issue

```
#<n> <exact issue title>

- <first action>
- <second action>
```

- **Line 1:** `#`, the issue number, one space, the exact issue title as on GitHub
  (`gh issue view <n> --json title --jq .title`). Line 1 is the same on every commit of the branch, also when the
  user asks for several commits for one issue. The action lines tell those commits apart; never write a custom line 1.
  In a batch (`/issue-kit:implement-issues`) the branch has one or more commits per issue, each with its own issue's
  `#<n> <title>`, on the branch that `batchBranchPattern` gives.
- **Line 2:** blank.
- **From line 3:** one action per line. Start each with `- ` and an imperative verb ("Add", "Fix", "Update",
  "Remove"). Keep the lines contiguous, with no blank lines between them. A single-action commit has one line.

Example (fictional):

```
#42 Export orders as CSV

- Add the CSV writer for orders
- Add the export command to the CLI
- Add tests for empty and large exports
```

### Case 2: the commit is not tied to an issue

This is the only format for a commit on `baseBranch`. All lines are actions that start with `- `, contiguous, with
no header line:

```
- Fix a typo in the README build section
- Update .gitignore for editor files
```

### Rules for both cases

- No trailers or signatures (`Co-Authored-By`, `Signed-off-by`, "Generated with…"). The repository turns off the
  attribution of Claude Code in `.claude/settings.json` (`attribution.commit` empty); `/issue-kit:init-config`
  prints that setting.
- Pass the message with `-F <file>`, or with a single `-m` that holds real newlines. Never use several `-m` flags:
  git puts blank lines between them and breaks the list.

## Stage the changes

- Review first: `git status --short` and `git diff --stat`. Read a per-file diff only when you need it to name the
  actions.
- Stage the intended files by name with `git add <paths>`. Never stage unrelated or unfinished files without
  confirmation; never run `git add -A` blindly.
- If a plan of the issue exists in `plans.dir` (a file whose name `plans.nameTemplate` gives for issue `<n>`), stage
  it in the same commit, with its checklist ticked to match the work.

## Inline or delegated

Run this skill inline when the user asks for a commit directly. Inside `/issue-kit:implement-issue` and
`/issue-kit:implement-issues` the whole skill runs in the agent of `roles.skillRunner`: branch, staging, message,
commit and the check. The caller gives it this skill's name, the compact facts (issue number and exact title, one line
per changed file), the exact files to stage, the branch and a scratch file path for the message. If you are the
skill runner, do not delegate again.

## Procedure

1. Determine the case: from the branch name, the workflow context, or ask for the issue number. On `baseBranch`
   without an issue it is Case 2.
2. Check or create the branch as above.
3. Review and stage.
4. Compose the message. Write it to a scratch file outside the repository (the session's scratch folder, or the
   system temp folder).
5. Run `git commit -F <file>`. A successful exit is the confirmation. Do not push.
6. Compare `git log -1 --format=%B` with the format above. On a deviation fix the commit you just made with
   `git commit --amend -F <file>`. Never amend an earlier commit or a pushed commit. When the repository has
   `issue-kit.config.json`, the issue-kit hook runs the same check after every `git commit` and reports violations
   back. A report from the hook means the same amend; it does not replace this check.
7. Report the short SHA and line 1.
