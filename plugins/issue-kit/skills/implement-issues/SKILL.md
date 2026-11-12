---
name: implement-issues
description: 'Take several small GitHub issues of the current repository one after another on one branch, each with the full implement-issue workflow and its own commit, then verify the branch once and ship one pull request. Started by the user only.'
disable-model-invocation: true
argument-hint: '<issue numbers in order> [--review-plans] [--ship]'
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, PowerShell, Agent, AskUserQuestion, Skill, mcp__ccd_session_mgmt__get_usage
---

# implement-issues

Take the GitHub issues `$ARGUMENTS` in the given order on **one branch**, each with the full `implement-issue`
workflow and its own commit. Then verify the whole branch once and ship it as **one pull request**. The batch runs
without review stops: it stops only on a question it cannot settle itself, and it reports every debatable decision at
the end.

The arguments are issue numbers in execution order (`/issue-kit:implement-issues 5 6 7`), plus optional flags:

- `--review-plans`: stop for the plan review of each issue, as `implement-issue` does.
- `--ship`: pre-authorise push, pull request, issue comments and acceptance ticks. Without it each of them waits for
  the user's go-ahead.

No issue numbers: recommend a batch with the `issue-kit:next-issue` skill (ready issues in order) and ask which to
take.

## Relation to implement-issue

Read `${CLAUDE_SKILL_DIR}/../implement-issue/SKILL.md` and its `references/` now. Do not invoke it with the Skill
tool: the user starts it, the model cannot. For every issue run that workflow (configuration, lane, understanding,
plan, implementation, build, verification) **with the differences below**. Everything not mentioned here applies
unchanged: the configuration, the context budget, the delegation to the agents of `roles`, the comment-hygiene
review, the documentation rules, the "requirements document first" rule, the plan file in `plans.dir`. When the
single-issue workflow changes, the batch inherits the change.

| `implement-issue` | In a batch |
|---|---|
| Step 0, per issue, with the start reading of the plan usage | Once, before the first issue |
| Branch created at the commit in step 12 | Created at the first issue's commit, then reused (see *Branch*) |
| Steps 5 to 7, plan review stop and compact milestone | Save the plan and continue; stop only with `--review-plans` |
| Step 9, build runner with scope `full` and the security review per issue | Build runner with scope `projects` (the test projects the change touches) per issue; scope `full` and the security review once at the end |
| Step 10, verification per issue | Per issue as written; slow UI tests once at the end |
| Step 11, result confirmation per issue | One confirmation for the whole batch |
| Steps 12 and 13, commit, push, comment, pull request per issue | A commit per issue; one comment per issue, one push and one pull request at the end. The task tick in a plan that covers several issues goes into each issue's commit |
| Step 12, session profile after the commit, amended into it | Once, after the batch confirmation and before the push; the record goes in as a separate commit (see *Ship*) |
| Step 14 | Once, at the end |

## 0. Preflight (once)

1. Read the configuration as `implement-issue` does.
2. Working tree and branch as in `implement-issue` step 0: uncommitted changes stop the batch; a clean tree →
   `git switch <baseBranch>` and `git pull --ff-only`.
3. Read every issue (`gh issue view`): body, comments, labels, state. A closed issue stops the batch. Choose each lane
   from its labels (`lanes`).
4. **Dependencies.** A blocker that is open and **earlier in the list** counts as met. Any other open blocker stops
   the batch; name it. If the list order contradicts a dependency, say so and stop.
5. **Size.** A batch is for small issues: at most 5, each of complexity S or M. A plan that comes back `L` stops the
   batch at that issue: report it, leave the finished commits, and suggest running that issue alone with
   `/issue-kit:implement-issue`.
6. Assign the issues to the user (`gh issue edit <n> --add-assignee @me`).
7. Read the plan usage once, silently, as in `implement-issue` step 0: the start reading of the session profile.

## Branch

Do not create the branch during preflight or planning; as in `implement-issue`, a branch comes into being only at a
commit. Create it from the fresh `baseBranch` at the **first issue's commit**, together with that commit, with the name
that `batchBranchPattern` gives (for example `5-7-cli-options` for `{first}-{last}-{slug}`). The slug names what the
issues of the batch have in common. Later commits reuse the branch. Never commit on `baseBranch`.

## Per issue (in list order)

1. Run `implement-issue` steps 1 to 10 with the differences above. Plan with `roles.planner`, implement with
   `roles.developer`, review the added comments, keep the plan file in the working tree.
2. **Questions.** A question that the issue, the requirements document, the code and sensible defaults do not settle
   stops the batch: ask the user, then continue from the same issue. A necessary change of the requirements document
   always stops the batch (propose the text, wait for approval). A choice that is yours to make but could be
   questioned (a UI presentation, a behaviour change beyond the acceptance list, a skipped refactor, a deviation from
   a convention) does **not** stop the batch: make it, record it in the plan's *Decisions* section and in a running
   list for the final report.
3. Call `roles.buildRunner` with scope `projects` and the test projects the change touches (build, then those tests;
   `commands.testProject`). If `commands.testProject` is empty, use scope `full`. Failures go back to implementation;
   do not commit red.
4. **Commit.** Starting the batch authorises the commits, one per issue; the first one also creates the branch (see
   *Branch*). Make one `roles.skillRunner` call with `issue-kit:git-commit` (Case 1: `#<n> <exact issue title>`, a
   blank line, action lines). It creates or checks the branch, stages exactly the files you list, commits, checks the
   message and reports the short SHA. A commit you make inline follows the same skill: load it with the Skill tool and
   run its check step; the commit message hook reports any violation right after the commit. List only that issue's
   changes: the plan file with its checklist ticked, the documentation the change updates, and the issue's task line
   in a plan that covers several issues (search `plans.dir` for `issues/<n>)` and tick the hit before the commit; no
   hit → nothing to tick).
5. The next issue starts from the committed state. Between issues, once the conversation passes about 40 tool calls,
   give the user a ready `/compact` command (focus: issue numbers and titles, acceptance lists, branch name, commits so
   far, the running decision list, changed files).

## Final verification (once, after the last commit)

Run on the branch as a whole, against `git diff <baseBranch>...HEAD`, in this order:

1. `roles.buildRunner` with scope `full`: build, all tests, format check. It returns the summary lines verbatim and
   the first failures.
2. **UI tests:** when the change touches a UI project, make sure that the build runner's summary shows its UI test
   run.
3. **Security review:** `roles.securityReviewer` (when set) on the branch diff when a changed file matches
   `securityReview.triggers`. Fix CRITICAL and IMPORTANT findings.
4. Verify again the acceptance items of every issue that the final run could affect.
5. Fix what fails or what the review finds as **additional commits**, each under the `#<n>` of the issue it belongs
   to (Case 1), then run the affected checks again.

## Report and confirmation

Present, in one message:

- a table: issue → commit → acceptance items → how verified → result;
- the verification results (build, tests, format, security review);
- **the list of debatable decisions**, each with the alternative considered;
- anything not covered or left out.

Ask whether the result is acceptable. If not, work on the affected issue again and verify again.

## Ship

Without `--ship` each step below needs the user's go-ahead; with it, run them in order. The question whether to save
the session profile (step 2) is asked even with `--ship`.

1. **Sync the base again:** `git fetch origin`. If `origin/<baseBranch>` moved, `git pull --ff-only` onto the branch
   (never rebase) and run the final verification again.
2. **Profile the session** once, as in `implement-issue` (`references/shipping.md`, *Profile the session*), with the
   arguments `save -WorkItem <first issue> -Lane <lane>`: the work item that the branch name gives, and the lane of
   the first issue. Leave out `-NoCommit`. A batch never amends, so on the user's yes the record goes in as a separate
   commit: one `roles.skillRunner` call with `issue-kit:git-commit` (Case 1 under the last issue of the batch,
   `#<last> <exact title>` with the action `- Save the session profile record`), staging only the record at the path
   the skill printed.
3. **Push** the branch (`git push -u origin <branch>`).
4. **One pull request** into `baseBranch`: one `roles.skillRunner` call with `issue-kit:open-pr`. Title
   `#<a> #<b> #<c> <shared summary>`; a description that starts with one `Closes #<n>` line per issue, then what
   changed, the debatable decisions and how it was verified. Do not repeat the acceptance tables of each issue.
5. **Issue comments:** one comment per issue for its lane, each with a link to the pull request: one
   `roles.skillRunner` call per issue with `issue-kit:github-issue`, which posts it. Post them after the pull request
   is open, so that the link is real. Tick the verified `- [ ]` boxes in each issue body yourself, with one call of
   the acceptance script per issue (`issue-kit:github-issue`, *Acceptance boxes*).
6. **CI:** check once with `gh pr checks <pr>`; never poll. Merging stays with the user.
7. Run `issue-kit:next-issue` with `-AssumeClosed` for every issue of the batch, and end with the same short message
   as `implement-issue` step 14 (merge the pull request, start a new session, the next `/issue-kit:implement-issue`
   or `/issue-kit:implement-issues`).

## Stops

The batch stops and reports, and leaves all finished commits in place, on: an unsettled question, a change of the
requirements document that needs approval, an open blocker outside the batch, a closed issue, a plan of complexity
`L`, a reproduction that fails (Bug lane), a build or test failure that two fix attempts do not resolve, or a change
that would need to touch an earlier issue's commit in a way that is not a plain follow-up. Never amend or rewrite a
commit already made in the batch; fix forward. The one exception is the message check that the skill runner runs on
the commit it has just made (`issue-kit:git-commit`, *Procedure*).
