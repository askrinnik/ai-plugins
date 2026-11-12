# Ship: steps 12 to 14 of implement-issue

**Get the go-ahead, delegate the action.** The agent of `roles.skillRunner` (cheap model, isolated context) carries
out the commit, the issue comment and the pull request, each end to end. It follows the whole skill: it composes the
text, runs the `git` or `gh` command and checks the result. Ask the user first. After the go-ahead make one call of
the skill runner for that one action. Give it:

- the skill name (`issue-kit:git-commit`, `issue-kit:github-issue`, `issue-kit:open-pr`);
- the compact facts you already hold: issue number and exact title, lane, one line per changed file, the acceptance
  table, the build and test results;
- the inputs that the skill's *Inline or delegated* section names;
- a scratch file path for the text, outside the repository, for every action, the commit included.

The push, the acceptance ticks and the CI check stay with you.

## 12. Commit and push

- **Sync the base again.** `git fetch origin`. If `origin/<baseBranch>` moved since step 0, pull it
  (`git pull --ff-only`; the uncommitted changes travel with you) and run step 9 again (a build runner call with
  scope `full`), so that nothing regressed against the newer base. Otherwise say that the base is unchanged.
- **Tick the plan** checklist in `plans.dir` to match the work. Also search `plans.dir` for the issue's link
  (`issues/<n>)`). A hit in another plan is a task line `- [ ] **<id>** ([#<n>](…))` of a plan that covers several
  issues; change it to `- [x]` once the user has confirmed the result in step 11. Both go into the same commit as the
  work.
- **Commit** after the user's go-ahead: one skill runner call with `issue-kit:git-commit`, the exact files to stage
  (the plan file included) and the branch. The branch is the one `branchPattern` gives, which the agent creates from
  the up-to-date `baseBranch`, or the existing branch you stayed on at the user's request (step 0). It reports the
  short SHA and line 1.
  - **Commit inline instead** for a trivial change, or for several commits that the user asked for: load
    `issue-kit:git-commit` with the Skill tool first (never copy the format from earlier commits), and run its check
    step (`git log -1 --format=%B` against the format) after every commit. Several commits for one issue all have the
    same line 1 `#<n> <exact issue title>`; the action lines tell them apart.
  - When the repository has `issue-kit.config.json` and `commitCheck.enabled`, the issue-kit `PostToolUse` hook
    checks the message of every new commit. When it reports a violation, fix the commit with
    `git commit --amend -F <file>` before the push. The hook does not replace the skill's own check.
- **Profile the session**, right after the commit and before the push:
  - Skip this bullet with one line when `profile.enabled` is `false`, or when the skill `profile.skill` (default
    `harness-kit:profile-session`) is not in this session's skill list.
  - Invoke the skill with the Skill tool in this main session, never in a subagent: a subagent has its own transcript
    and would profile that. The skill calls `get_usage` again first, so the transcript also holds the end reading of
    the weekly limit. The push, the issue comment and the pull request come after it and are not part of the profile.
  - Show the result in a few lines: model calls, cost units and units per call, the estimated cost in USD (an
    estimate at API list prices, not a subscription charge), the largest activities, idle rebuilds and compactions,
    and the share of the weekly limit when there is one.
  - **Ask whether to save the profile and add it to the commit,** and say in the question how it will be added (see
    below). If the user declines, nothing is written.
  - On yes, invoke the skill with the arguments `save -WorkItem <n> -Lane <lane> -NoCommit`, where `<lane>` is `Bug`,
    `Feature` or `Test-authoring`. The skill prints `Saved session <id> to <path>.` Take the record path from that
    line; do not assume a folder. Then add the record:
    - **The commit is not pushed yet** (no upstream branch, or `git branch -r --contains HEAD` is empty), the usual
      case: `git add <path>`, write the current message (`git log -1 --format=%B`) plus one line
      `- Save the session profile record` to a scratch file, and run `git commit --amend -F <file>`. `-NoCommit`
      leaves the record without a commit id, because the amend changes that id.
    - **The commit is already pushed** (a session that stayed on its branch after the pull request): commit the record
      as a new commit, with one skill runner call with `issue-kit:git-commit` after the user's go-ahead. Never amend a
      pushed commit.
- **Push** (`git push -u origin <branch>`) after the user's go-ahead.

## 13. Issue comment, acceptance boxes, pull request

- **Issue comment.** After the user's go-ahead, one skill runner call with `issue-kit:github-issue` (Bug → *Root
  Cause / Resolution / Verification*; Feature and Test-authoring → *Implementation / Acceptance Criteria /
  Verification*). It posts the comment and reports its URL.
- **Acceptance boxes.** After the user's go-ahead, tick the verified items of the acceptance section
  (`## <issueSections.acceptance>`) with one call of the acceptance script (`issue-kit:github-issue`, *Acceptance
  boxes*), with their positions. Leave unverified items unticked and name them from the script's output. Skip this
  when the body has no checklist.
- **Pull request.** After the user's go-ahead, one skill runner call with `issue-kit:open-pr`, the head branch and the
  posted comment. It opens the pull request into `baseBranch` (title `#<n> <exact title>`, body with `Closes #<n>`)
  and reports the URL. Give the URL to the user.
- **CI.** Check once with `gh pr checks <pr>`. If checks are still running, say so: the desktop app can watch CI. Do
  not poll in a loop. If a check fails, report the failing job and the first error, and fix it on the same branch
  after the user agrees.
- The user merges the pull request. Do not merge unless the user asks.

## 14. Recommend the next issue

- Run `issue-kit:next-issue` with `-AssumeClosed <n>` (this issue closes when its pull request merges).
- End with a short, ready-to-act message:
  1. Merge pull request #<pr> (after CI is green).
  2. Start a new session (`/clear` or a new chat).
  3. Run `/issue-kit:implement-issue <next>`: <title>. Step 0 of that run switches to `baseBranch` and pulls the
     merge.
- Mention up to two alternatives and anything that waits for this pull request.
