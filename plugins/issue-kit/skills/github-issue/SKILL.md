---
name: github-issue
description: 'Read a GitHub issue of the current repository (body, comments, related issues, requirement links), establish its lane and acceptance list, post a summary comment for the work just completed (a root-cause analysis for a bug, an implementation summary for other issues) and tick the verified acceptance boxes. Use when a workflow starts from a GitHub issue number or must record the result of the work on that issue, including the comment step of /issue-kit:implement-issue.'
argument-hint: '[issue number] (optional; taken from the current branch name)'
---

# github-issue

Issue reads and writes go through the `gh` CLI, in the repository of the current folder
(`gh repo view --json nameWithOwner --jq .nameWithOwner`).

## Read the configuration

Run once, from the repository root:

```bash
pwsh -NoProfile -File "${CLAUDE_SKILL_DIR}/../../scripts/Get-IssueKitConfig.ps1"
```

Use `issueSections`, `lanes`, `prd`, `plans.dir`, `branchPattern` and `shipLanguage`. If the script reports a
configuration error, stop and show the message.

## When to use

- A workflow starts from an issue number (for example `/issue-kit:implement-issue 12`).
- The result of the work must be recorded on the issue as a comment. The comment is the lasting record on the issue;
  the pull request description is built from it.

## Read an issue

Take the issue number `<n>` from the argument or the calling workflow. Otherwise take it from the current branch name
(`branchPattern`). If it is still not clear, ask.

1. Fetch the issue in one call: `gh issue view <n> --json number,title,state,labels,milestone,body,comments,assignees`.
2. Read the comments: requirements are often refined there, not in the body.
3. If the issue links a parent or has sub-issues, read them too, so that the scope boundary is clear. Work on this
   issue only, not on the whole parent.
4. If the issue is closed, stop and confirm with the user before you do anything.
5. Note the sections of the body:
   - `## <issueSections.requirements>`: the requirement ids (`prd.idPattern`) and the sections of the requirements
     document (`prd.path`) that the issue links. Skip this when `prd.path` is empty.
   - `## <issueSections.acceptance>`: the acceptance criteria, a `- [ ]` list.
   - `## <issueSections.dependencies>`: the blocking issues.

### Determine the lane by label

The labels select the lane of the `implement-issue` workflow:

- **Bug lane:** a label of `lanes.bug`. A defect to reproduce and fix at its root cause.
- **Test-authoring lane:** a label of `lanes.testAuthoring`, and the issue asks only for tests of behaviour that
  already exists. A change to CI workflows, configuration or documentation is not test-authoring, even with such a
  label: it takes the Feature lane.
- **Feature lane:** every other issue.

If the labels and the issue text disagree, stop and confirm the lane with the user.

### Establish the acceptance criteria

- Restate the requirement in a sentence or two: what is true when this issue is done.
- Turn it into an explicit, checkable list, one line per observable behaviour: the items of the acceptance section
  verbatim, plus any observable behaviour that the requirements document requires and the issue omits (marked as
  added).
- Flag gaps; do not invent. If something material is undefined in both the issue and the requirements document, ask
  the user before you continue. Make routine naming and structure decisions yourself.

## Post the result comment

Write it in `shipLanguage`, in GitHub Markdown. Base it strictly on what was changed and verified; never invent
details. No screenshots, no local absolute paths, no secrets. Do not restate the issue; report the outcome.

- Take every number, name and list from the facts you work from, verbatim. Do not recount, merge, reattribute or
  extend them. If something looks inconsistent, keep it as given and point it out.
- The *Acceptance Criteria* table has one row per acceptance item of the issue: exactly those items, in their order.
  Never add rows.

**Bug lane:**

```markdown
## Root Cause
<one or two paragraphs: the defect, not the symptom, naming the types and methods involved>

## Resolution
<one intro sentence>

**Changes**
- `path/File.ext`: <what changed there>

**Key note:** <a decision or pitfall that is not obvious, if any>

## Verification
<table or bullets: the tests that reproduce the bug and now pass, other tests, build>
```

**Feature lane and Test-authoring lane:**

```markdown
## Implementation
<one intro sentence>

**Changes**
- `path/File.ext`: <what changed there>

**Key note:** <a decision or pitfall that is not obvious, if any>

## Acceptance Criteria
| Criterion | How it is satisfied |
|---|---|
| <criterion from the issue> | <test name, command or behaviour> |

## Verification
<tests run and results, format check, build>
```

When the work changed the requirements document, add `**Requirements:** updated to <version>: <what changed>` under
*Key note*. Mention the plan file in `plans.dir` when there is one.

Write the body to a scratch file outside the repository (the session's scratch folder, or the system temp folder).
Post it after the user's go-ahead:

```bash
gh issue comment <n> --body-file <file>
```

The command prints the comment URL. Report it; that is the confirmation. Do not read the issue again to check.

## Acceptance boxes

After the comment, and after the user's go-ahead, tick the verified items of the acceptance section in the issue body
with the script. Make one call; do not read or rewrite the body by hand:

```bash
pwsh -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/Set-AcceptanceChecks.ps1" -Issue <n> -Items 1,2,4
```

- The acceptance section is the first heading `## <issueSections.acceptance>`, `## Acceptance criteria` or
  `## Acceptance`. A note in parentheses after the heading is allowed.
- `-Items` are the positions of the verified checkboxes in that section: 1-based, in document order, as one
  comma-separated value.
- The script changes only those `- [ ]` marks. It refuses to write if anything else in the body would differ, and it
  never unticks.
- Its output lists every checkbox with `ticked now`, `already ticked` or `left unticked`. Name the unticked ones to
  the user. `-DryRun` shows the result without editing.
- Skip this step when the body has no checklist.

## Inline or delegated

Run this skill inline when the user asks for a comment directly. Inside `/issue-kit:implement-issue` and
`/issue-kit:implement-issues`, after the user's go-ahead, *Post the result comment* (composing and posting) runs in
the agent of `roles.skillRunner`. The caller gives it this skill's name, the compact facts (issue number and title,
lane, changed files with one line each, the acceptance items with how each was verified or the root cause, build and
test results, the pull request URL if it exists) and a scratch file path for the body. The agent posts the comment
and returns its URL. Reading the issue and ticking the acceptance boxes stay with the caller. If you are the skill
runner, do not delegate again.
