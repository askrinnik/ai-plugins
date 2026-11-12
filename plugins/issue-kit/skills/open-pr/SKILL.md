---
name: open-pr
description: 'Open a GitHub pull request by the issue-kit conventions of the current repository: target branch, title, the Closes keyword and what the description holds. Use when creating or updating a pull request, on its own or as the pull-request step of /issue-kit:implement-issue and /issue-kit:implement-issues. Covers pull requests only; commit mechanics are in the git-commit skill.'
argument-hint: 'Optional: the issue number the pull request resolves'
---

# open-pr

How to open a pull request in a repository that uses issue-kit. Pull-request mechanics only.

Never create, update or merge a pull request without the user's explicit go-ahead.

## Read the configuration

Run once, from the repository root:

```bash
pwsh -NoProfile -File "${CLAUDE_SKILL_DIR}/../../scripts/Get-IssueKitConfig.ps1"
```

Use `baseBranch`, `branchPattern`, `batchBranchPattern`, `shipLanguage` and `plans.dir`. If the script reports a
configuration error, stop and show the message.

## Tooling

Use the `gh` CLI (`gh pr create`, `gh pr view`, `gh pr checks`). Write the description to a scratch file outside the
repository (the session's scratch folder, or the system temp folder) and pass it with `--body-file`. Do not put long
text on the command line.

## Target, title and linkage

- **Source:** the issue branch (`branchPattern`), pushed with `git push -u origin <branch>` after the user's
  go-ahead.
- **Target:** `baseBranch`.
- **Title:** `#<n> <exact issue title>`, the same as line 1 of the commits.
- **Linkage:** the description holds `Closes #<n>` on its own line, so GitHub links the issue and closes it when the
  pull request is merged. One pull request resolves one issue, except a batch (`/issue-kit:implement-issues`): its
  branch comes from `batchBranchPattern`, the title is `#<a> #<b> #<c> <shared summary>`, and the description starts
  with one `Closes #<n>` line per issue.
- **Merge:** the user merges. Do not merge unless the user explicitly asks.
- After `gh pr create`, report the pull request URL. A successful `gh pr create` is its own confirmation; do not read
  the pull request again to check the title.

## Description

Write it in `shipLanguage`, in Markdown. In priority order; when space is tight, drop from the end:

1. **What and why.** For a bug: symptom, root cause, why this fix. For a feature: what it does and the decisions a
   reviewer cannot see in the diff.
2. **Reviewer attention.** Risky paths, behaviour changes, residual risks, deviations from the plan, changes of the
   requirements document.
3. **Verification.** Tests, build, manual checks, in two or three lines.
4. `Closes #<n>`, and a link to the plan file in `plans.dir` if there is one.

Do not repeat what the issue comment already holds (the full root-cause analysis, the acceptance table, the file
list). Build the description from that comment, shorter, and link to it. Keep it under about 3000 characters.

## After opening

- Check CI once with `gh pr checks <pr>`. If it is still running, say so and stop; the desktop app can watch CI. Do
  not poll in a loop.
- If CI fails, report the failing job and the first error lines (`gh run view <run> --log-failed`, captured to a file
  and searched). Fix it on the same branch after the user agrees.

## Inline or delegated

Run this skill inline when the user asks for a pull request directly. Inside `/issue-kit:implement-issue` and
`/issue-kit:implement-issues`, after the user's go-ahead and after the push, the whole skill (composing and
`gh pr create`) runs in the agent of `roles.skillRunner`. The caller gives it this skill's name, the issue numbers and
exact titles, the head branch, the posted issue comment (in a batch, where the comments follow the pull request, a
short summary per issue) and a scratch file path for the body. The agent opens the pull request and returns its URL.
The CI check stays with the caller. If you are the skill runner, do not delegate again.
