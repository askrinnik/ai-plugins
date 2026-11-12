---
name: next-issue
description: 'Recommend the next GitHub issue to implement in the current repository: the first open issue whose blocking issues are all closed and that has no open pull request yet, ordered by the order code of the title when the repository configures one, plus the issues that become ready once pending pull requests merge. Use when the user asks what to do next or which issue to take, at the end of /issue-kit:implement-issue, and when /issue-kit:implement-issue or /issue-kit:implement-issues starts without an issue number.'
argument-hint: 'Optional: issue numbers to treat as closed (for example the one just shipped)'
---

# next-issue

Recommends what to implement next, from the issue dependencies recorded on GitHub.

## How the order is defined

- **Dependencies** are GitHub "blocked by" relations between issues. The issue body can mirror them in its section
  `## <issueSections.dependencies>` of the issue-kit configuration. An issue closes only when its pull request is
  merged, so "closed" means "its code is in the base branch".
- **Order** among ready issues comes from `ordering.titleCodePattern`: its capture groups, compared as numbers, then
  the issue number. Issues without a code go last. Without a pattern the order is the issue number.
- An issue with an open pull request is in progress. The skill never recommends it.

## Procedure

1. Run, from the repository root:

   ```bash
   pwsh -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/Get-NextIssue.ps1" [-AssumeClosed <n>[,<n>…]] [-Top 3]
   ```

   Pass `-AssumeClosed <n>` for an issue whose pull request is open but not merged yet.
   `/issue-kit:implement-issue` does this for the issue it has just shipped. If the script reports a configuration
   error, stop and show the message: it names the file and the key.

2. Present the result in a few lines:
   - the recommended issue: number, title, milestone, and the ready-to-paste command
     `/issue-kit:implement-issue <n>`;
   - up to two alternatives that are also ready;
   - the issues that become ready after a pending pull request merges, with the pull request;
   - if the recommendation depends on an assumed-closed issue, say that its pull request must be merged first.

3. Recommend that the next issue starts in a new session (`/clear` or a new chat), after the pending pull request is
   merged. Then the next issue starts from an up-to-date base branch and a small context.

## Notes

- The script makes one GraphQL query through `gh`. It needs no other tool.
- If an issue body lists a dependency that has no "blocked by" relation, or the reverse, report the mismatch: the two
  must agree. To fix it, the user's go-ahead is necessary:
  `gh api -X POST repos/<owner>/<repo>/issues/<n>/dependencies/blocked_by -F issue_id=<id of the blocker>`.
- When the user creates a new issue, set both the dependencies section and the "blocked by" relations, or the order
  breaks without a warning.
