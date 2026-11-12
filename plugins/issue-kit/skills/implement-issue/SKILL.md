---
name: implement-issue
description: 'Take one GitHub issue of the current repository end to end: dependencies and requirements check, plan with review, implementation with tests, build-and-test gate, verification, session profile, issue comment, pull request and the next-issue recommendation. Started by the user only.'
disable-model-invocation: true
argument-hint: '[issue number] [optional: "stay on current branch"]'
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, PowerShell, Agent, AskUserQuestion, Skill, mcp__ccd_session_mgmt__get_usage
---

# implement-issue

Take GitHub issue `$ARGUMENTS` of the current repository end to end: read it, check its dependencies and the
requirements document, plan, implement with tests, verify, profile the session, record the outcome on the issue,
open the pull request and recommend the next issue.

- If `$ARGUMENTS` holds no issue number, run the `issue-kit:next-issue` skill and ask which issue to take before you
  do anything else.
- If `$ARGUMENTS` asks to stay on the current branch (for example "stay", "no switch", "continue on the current
  branch"), skip the switch to the base branch in step 0.

There are two checkpoints with the user: the plan review and the result confirmation. Every outward action (commit,
push, comment, pull request) needs the user's go-ahead.

The issue's labels select the **lane** in step 2. Steps marked **Bug lane**, **Feature lane** or **Test-authoring
lane** apply only to that lane; unmarked steps apply to all lanes.

## Configuration

Read the configuration first, from the repository root:

```bash
pwsh -NoProfile -File "${CLAUDE_SKILL_DIR}/../../scripts/Get-IssueKitConfig.ps1" -Sources
```

If it reports an error, stop and show the message: it names the file and the key. Keep the values in mind; this
skill names them by key, for example `baseBranch` or `commands.build`. If the repository has no
`issue-kit.config.json`, say in one line that the defaults apply and that `/issue-kit:init-config` drafts the file.

The skill orchestrates other skills; it does not repeat their mechanics:

- **`issue-kit:github-issue`**: read the issue, establish the acceptance list, post the result comment, tick the
  acceptance boxes.
- **`issue-kit:git-commit`** and **`issue-kit:open-pr`**: create the issue branch and commit; open the pull request.
- **`issue-kit:next-issue`**: recommend what to take when no issue number is given, and what comes next.
- **`roles.debugSkill`** and **`roles.testsSkill`**, when set: reproduce and diagnose a defect; choose the test layer
  and write the tests.

## Delegation

Noisy or specialised work goes to subagents, so that their raw output stays out of this conversation. Pass the agent
name of the role as `subagent_type`. A plugin agent has the plugin prefix (`issue-kit:build-runner`).

| Role | Agent | Model | Steps |
|---|---|---|---|
| Plan | `roles.planner` | Opus | 4 |
| Design of a cross-layer change | `roles.architect` (optional) | the agent's own | 4 |
| Implement | `roles.developer` | Sonnet; Opus for complexity `L` | 8 |
| Build, tests and format | `roles.buildRunner` | Haiku | 9, 12 |
| Security review (when triggered) | `roles.securityReviewer` (optional) | the agent's own | 9 |
| Commit, issue comment, pull request (after the user's go-ahead) | `roles.skillRunner` | Haiku | 12, 13 |
| Broad code search | `Explore` (summary of at most 30 lines) | default | 3 |

- An empty optional role means: skip that part and say so in one line where it applies.
- **You keep every gate:** the plan review, both confirmations with the user, the user's go-ahead before every
  outward action, the push, the acceptance ticks and the CI check. The developer's "passed" is input, not proof: the
  build and the tests run again in the build runner, independently of it.
- Give each subagent only the compact facts it needs (issue number and exact title, lane, plan file path, acceptance
  list, decisions, the configuration values of its task), not this conversation.
- For a trivial change (a few lines, one file) you may plan or implement inline instead of delegating.

## Context budget

Read `references/context-budget.md` (in this skill's folder) before step 0 and follow it in every step. It defines
the compact milestones after steps 7, 9 and 11, the runaway guard, narrow reading, small tool output and the rule
that scratch paths stay outside the repository.

## 0. Start from an up-to-date base branch

The previous issue usually leaves you on its own branch, and its pull request may be merged since. Unless the user
said otherwise:

- Check the working tree (`git status --short`) and the current branch (`git branch --show-current`).
- **Uncommitted changes:** stop and report them. Ask whether to commit, stash or discard them. Never switch branches
  with a dirty tree; never discard changes on your own.
- **Clean tree:** `git switch <baseBranch>` and `git pull --ff-only`, also when you are already on `baseBranch`. A
  stale base means building on files that changed since.
  - If the branch you left has commits that are not in `baseBranch` (`git log <baseBranch>..<branch> --oneline` after
    the pull), mention it: its pull request is probably not merged yet. The commits stay on that branch.
  - If the fast-forward pull fails (diverged history), stop and report. Never force.
- **Stay on the current branch only when the user explicitly says so** for this issue. Then skip the switch, pull the
  current branch if it tracks a remote, and note that the base may be stale.
- Work in the working tree on `baseBranch`. Do not create the issue branch now: it comes into being at the first
  commit (step 12), from the latest `baseBranch`.
- **Read the plan usage once, silently.** When the host has the plan-usage tool (`get_usage` of the Claude desktop
  app; load its schema first if the host defers it), call it in this main session without asking and without
  reporting the result. The result stays in the session transcript, where the session profile of step 12 finds it as
  the start reading. Without the tool, skip this silently.

## 1. Read the issue

- If no issue number was given, run `issue-kit:next-issue`, present its recommendation and ask which issue to take.
  Do nothing else until the user picks one.
- Use `issue-kit:github-issue` to read issue `<n>`, with its comments.
- If the issue has a parent or sub-issues, the scope is this issue, not the whole parent.
- If the issue is closed, stop and say so.
- Note the requirement links (`## <issueSections.requirements>`), the task, the acceptance criteria
  (`## <issueSections.acceptance>`) and the dependencies (`## <issueSections.dependencies>`).

## 2. Check dependencies, determine the lane, take ownership

- **Dependencies.** Read the blocking issues: `gh api graphql` for `blockedBy`, and the numbers in the dependencies
  section. If a blocker is still open, stop: name it, say whether it has an open pull request, and ask how to
  continue. Do not start on top of unmerged work unless the user explicitly says so. If the body and the relations
  disagree, mention it.
- **Lane.**
  - **Bug lane:** a label of `lanes.bug`. Reproduce, fix the root cause, guard it with a regression test, post a
    root-cause comment.
  - **Test-authoring lane:** a label of `lanes.testAuthoring`, and the issue asks only to add or extend tests for
    behaviour that already exists. No production code is expected; the tests are the deliverable. A change to CI
    workflows, configuration or documentation is not test-authoring, even with such a label: it takes the Feature
    lane.
  - **Feature lane:** every other issue. Acceptance list, plan, build, implementation comment.
  - State the lane and why in one line. If the labels and the issue text disagree, ask before you continue.
- **Ownership.** Assign the issue to the user: `gh issue edit <n> --add-assignee @me`. This is the one issue edit that
  needs no separate confirmation; it changes no content.

## 3. Understand the problem

**All lanes:** if `prd.path` is set, read the sections of the requirements document that the issue links, and only
those. The requirements document is the scope authority. If `prd.path` is empty, the issue is the scope authority.

**Bug lane: reproduce.**
- Reproduce before you plan a fix, preferably with a **failing test** in the layer that owns the decision, or with a
  run of the program against a temporary folder that captures the exit code, the output and the log. Follow
  `roles.debugSkill` when it is set.
- If it cannot be reproduced as described, report what you tried and ask how to continue.

**Feature lane and Test-authoring lane: acceptance and current state.**
- Use `issue-kit:github-issue` to restate the requirement in a sentence or two and to build the acceptance list: the
  issue's criteria verbatim, plus any observable behaviour that the requirements document requires and the issue
  omits (marked as added).
- **Flag gaps; do not invent.** If something material is undefined in both the issue and the requirements document,
  ask before you plan. Routine naming and structure decisions are yours.

**Requirements document first** (only when `prd.path` is set). If the issue cannot be done without behaviour that the
document does not describe, or the issue contradicts it, stop and propose the change of the document: the text, and
the version and history entry if the document keeps them. Implement only after the user approves; the document edit
is part of this issue's change. If the issue text is out of date against the document, propose to update the issue
after the document.

## 4. Draft the plan

- Delegate the research to `roles.planner`. Give it: issue number and exact title, lane, the requirement sections and
  ids (if any), the acceptance list (or the reproduced failure and the failing test), the decisions already made with
  the user, `prd.path`, and `plans.language`. It returns the plan text in `plans.language`, in the shape it defines,
  with a **complexity** of `S`, `M` or `L`.
- For a trivial change you may draft the plan inline, in the same shape. For a large or multi-layer change you may
  use `roles.architect` (when set) to shape it, but keep the final plan in the planner's shape.
- **Bug lane:** the root cause, the types and methods to change, the regression risk, and the test that reproduces
  the bug and keeps it fixed.
- **Test-authoring lane:** the test classes and cases to add, the fixtures and helpers they reuse, and confirmation
  that no production code changes.
- **Feature and Test-authoring lanes: check the coverage against the code, not only against the issue text.** For
  every type, command or view the plan touches or tests, list its inputs and code branches (required and optional
  options, success, failure, empty and cancelled paths, boundary values) and compare them with the scenarios of the
  issue. Add each gap to the plan (and to the acceptance list), or name it under *Out of scope*. Never skip a gap
  without a word. Make small additions that are clearly in scope without asking.
- If the plan lists *Requirements changes* or *Open questions*, resolve them with the user at the review in step 5.

## 5. Save the plan and get it reviewed

- Save the plan in `plans.dir`, with the name that `plans.nameTemplate` gives. `{type}` is the first group of
  `plans.typeLabelPattern` that matches a label (no match: `feature`), `{n}` the issue number, `{slug}` a short
  kebab-case slug of the English title. This repository file is the deliverable; a plan-mode scratch file elsewhere
  does not replace it. If the environment blocks writes while planning, write the file as soon as writes are allowed
  and say so.
- Header of the file: issue link, title, lane, complexity, date.
- Show the user the path and a short summary (goal, approach, complexity, open questions) and ask for a review. Do not
  touch application code yet.

## 6. Revise on feedback

Apply the feedback to the same plan file and present it again. Repeat until the user approves.

## 7. Approved

- Record the decisions of the review in the plan file (section *Decisions*).
- **Milestone:** give the user the step-7 `/compact` command from `references/context-budget.md`.

## 8. Implement

- Delegate non-trivial work to `roles.developer`. **Choose its model from the plan's complexity:** `S` or `M` → the
  agent's default; `L` → pass `model: "opus"` in the Agent call. Give it the plan file path, the acceptance list, the
  decisions of the review, the lane, and the commands of `commands`. It implements and tests, and returns a change
  summary; it never commits, pushes or posts.
- For a trivial change, implement inline.
- **Feature lane:** wire the whole slice that the issue covers, as `CLAUDE.md` describes the layers of the project.
  A half-wired feature is not done.
- **Test-authoring lane:** the tests are the deliverable; do not touch production code. If the tests show that the
  behaviour is broken, stop and tell the user: that is a separate defect, not part of this issue.
- **New behaviour ships with tests** (`roles.testsSkill` when set, and the test rules of `CLAUDE.md` and
  `.claude/rules/`). **Bug lane:** the reproducing test of step 3 is part of the change.
- If the plan turns out wrong in the code, say so, update the plan file, and confirm before you diverge materially.
- Update the documentation that the change affects in the same change, as `CLAUDE.md` and `.claude/rules/` say.

## 9. Build and test

Run the gate independently of the developer, even if it reported success:

- **Build, tests, format:** one call to `roles.buildRunner` with scope `full`, the commands of `commands`, and a
  scratch folder outside the repository. It returns the summary lines of the tools verbatim with the first errors.
  Everything must be green. On a failure, give the reported errors back to `roles.developer` (or fix a trivial cause
  inline) and call the build runner again; do not run the commands yourself to see the same output. Give the build
  runner a subfolder of its own in your scratch folder (for example `<scratch>/build`), the same one on every call.
  If a command is empty, the build runner reports `NOT CONFIGURED`; name that part as not done in step 11.
- **Review the comments this change adds** when `commentReview.globs` is not empty, also those the developer wrote:
  `git diff -U0 -- <globs>`, the added lines (`+`) that hold a comment. Check each against the comment-hygiene rules
  (no change narration, no issue references, no line numbers, no repetition of the code) and fix what fails.
- **Security review:** when `roles.securityReviewer` is set and a changed file matches `securityReview.triggers`, run
  that agent on the working tree and fix CRITICAL and IMPORTANT findings.
- **This step is not optional.** Run the build runner with scope `full` on every issue, and the security review
  whenever its triggers match. The user's go-ahead to skip the plan review or to go straight through the workflow does
  not cover skipping them, and "no code changed" is not a reason. Skip a part only when the user explicitly says so
  for this issue, and name it in step 11 as not done.
- **Milestone:** give the user the step-9 `/compact` command.

## 10. Verify

- **Bug lane:** the reproducing test passes; run the original reproduction again and confirm that the failure is
  gone.
- **Feature lane:** verify **every** acceptance item and record how: a named test, a command with its observed
  output, or a run of the program against a temporary folder (exit code, output, files on disk, log entries).
  Exercise the obvious negatives that the requirements define: invalid input or configuration, a missing tool, a
  failure, cancellation, a dry run that changes nothing. Verify an item without runtime behaviour (a CI workflow,
  configuration, documentation) with a command, a test or the CI run of the pull request, and record how. An item that
  only the CI run can confirm stays open until it has.
- **Test-authoring lane:** the new or changed tests appear in the build runner's summary, pass, and assert the
  intended behaviour. A test that passes without asserting anything is not done.
- UI issues: the UI tests that the plan names; manual inspection of the running application only when the user asks
  for it.
- **This step is not optional.** The user's go-ahead to skip the plan review does not cover it, and a green test run
  does not replace the record per item. Skip an item only when the user explicitly says so for this issue, and name it
  in step 11 as not verified.
- If something fails, go back to step 8 (or step 4 if the approach must change), then run steps 9 and 10 again.

## 11. Ask for confirmation

- **Bug lane:** what was wrong (root cause), what was fixed, how it was verified.
- **Feature and Test-authoring lanes:** what was implemented, and the acceptance list as a table: item → how verified
  → result. State anything not covered or left out.
- Ask whether the result is acceptable. If not, go back to step 8 (or 4).
- **Milestone:** after the confirmation, give the user the step-11 `/compact` command.

## 12 to 14. Ship

Read `references/shipping.md` (in this skill's folder) and follow it: commit, session profile, push, issue comment,
acceptance boxes, pull request, CI check and the next-issue recommendation.

> If the build tools or `gh` are not available in the session, produce the plan, the change and the comment text so
> that they can be applied by hand, and say which steps were skipped.
