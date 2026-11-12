---
name: init-config
description: 'Draft issue-kit.config.json for the current repository from its project files, labels and recent issues, show the draft, write it after the user confirms, and print the .claude/settings.json additions; with "check", validate an existing configuration (keys, paths, commands, agents and skills of roles). Use when the user sets up issue-kit in a repository, asks to create or check the issue-kit configuration, or a workflow reports a configuration problem.'
argument-hint: '[check]'
---

# init-config

Sets up or checks the issue-kit configuration of the current repository. Every key is documented in
`${CLAUDE_SKILL_DIR}/../../CONFIGURATION.md`; read it before you draft.

## check

If the argument is `check`, run from the repository root and stop after step 2:

```bash
pwsh -NoProfile -File "${CLAUDE_SKILL_DIR}/../../scripts/Test-IssueKitConfig.ps1"
```

1. The script prints one line per check (`OK`, `WARN`, `FAIL`) and a result line. It reads the three layers, checks
   keys and types, `prd.path` and `plans.dir`, the program of each command, the agents and skills of `roles`, and the
   base branch.
2. Report the `FAIL` and `WARN` lines in plain words, each with the fix (the key to change and the value). A name of
   another plugin is not checked by the script: compare it with the agent and skill lists of this session and say
   whether it is there. Change nothing unless the user asks.

## Draft a configuration

Without an argument:

1. **Existing file.** If `issue-kit.config.json` exists in the repository root, say so, run the check above, and ask
   whether to revise it or stop. Revise only the keys the user names.
2. **Collect the facts.** Read narrowly; run one command per tool call.
   - **Stack and commands:** look for the project files in the root and one level down (`*.sln`, `*.slnx`,
     `*.csproj`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`, `build.gradle*`, `Makefile`)
     and for the build section of `CLAUDE.md` and `README.md`. Draft `commands.build`, `commands.testFull`,
     `commands.testProject` (with `{project}`) and `commands.format` (a check mode that changes nothing). Prefer the
     commands that `CLAUDE.md` gives. Leave a command empty when you cannot find a reliable one, and say so.
   - **Base branch:** `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`); else the current
     default branch from `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`.
   - **Branch names:** `git branch -a --format=%(refname:short)` and the last 30 merged pull requests
     (`gh pr list --state merged --limit 30 --json headRefName --jq .[].headRefName`). Keep the default patterns
     unless the names clearly follow another pattern.
   - **Labels:** `gh label list --limit 100 --json name --jq .[].name`. Choose `lanes.bug` (for example `bug`,
     `defect`) and `lanes.testAuthoring` (for example `type:test`, `tests`) from them; adapt
     `plans.typeLabelPattern` if the type labels have another form.
   - **Issue headings:** the bodies of the last 20 issues
     (`gh issue list --state all --limit 20 --json body --jq .[].body`). Find the headings (`## …`) of the
     requirements links, the acceptance checklist and the dependencies; take them verbatim, in the language of the
     repository.
   - **Order codes:** the titles of the open issues (`gh issue list --limit 50 --json title --jq .[].title`). If most
     titles start with a code such as `P1.4:`, draft `ordering.titleCodePattern` with one capture group per number.
   - **Requirements document:** a file such as `docs/PRD.md`, `docs/requirements.md` or `SPEC.md`, or the one that
     `CLAUDE.md` names. If found, set `prd.path` and draft `prd.idPattern` from the ids in it.
   - **Plans:** an existing folder of plan files (`docs/plans/`, `.ai/plans/`); keep `plans.dir` at the default
     otherwise. Draft `plans.language` from the language of the existing plans, else leave the default.
   - **Roles:** agents in `.claude/agents/` and skills in `.claude/skills/`. Offer an architect, a security reviewer,
     a debugging skill and a test-writing skill when they exist; never invent names.
   - **Checks:** draft `securityReview.triggers` (infrastructure, authentication, CI workflows, package manifests)
     only when `roles.securityReviewer` is set, and `commentReview.globs` from the source file types.
3. **Show the draft.** Write only the keys that differ from the defaults. Give one line per key on where the value
   came from. List what you could not find. Ask the user to confirm or change it.
4. **Write** `issue-kit.config.json` in the repository root only after the user confirms. Then run the check above
   and report its result.
5. **Print the settings additions** for `.claude/settings.json` of the repository, as a block the user can merge. Do
   not edit the settings file unless the user asks:

   ```json
   {
     "enabledPlugins": { "issue-kit@ai-plugins": true },
     "attribution": { "commit": "", "pr": "" },
     "permissions": {
       "allow": [
         "Bash(pwsh -NoProfile -File *issue-kit*)",
         "PowerShell(pwsh -NoProfile -File *issue-kit*)",
         "Bash(git status *)", "Bash(git diff *)", "Bash(git log *)", "Bash(git branch *)", "Bash(git fetch *)",
         "Bash(git add *)", "Bash(git switch *)", "Bash(git pull --ff-only*)", "Bash(git commit *)",
         "Bash(gh issue view *)", "Bash(gh issue list *)", "Bash(gh issue edit *)", "Bash(gh issue comment *)",
         "Bash(gh pr view *)", "Bash(gh pr list *)", "Bash(gh pr checks *)", "Bash(gh pr create *)",
         "Bash(gh api graphql *)", "Bash(gh label list *)", "Bash(gh repo view *)"
       ],
       "ask": ["Bash(git push *)", "Bash(gh pr merge *)"]
     }
   }
   ```

   Add one `Bash(<command>)` rule per configured command of `commands` (for example `Bash(npm test*)`), and the same
   rules with `PowerShell(` on Windows. Say that `attribution` is empty because the commit format has no trailers,
   and that `git push` stays an `ask` rule because the workflow asks before every push anyway. The marketplace name
   `ai-plugins` is the one the user registered; if the user registered it under another name, use that name.
6. **Session profile.** If the skill `harness-kit:profile-session` is in this session's skill list, offer settings
   for `profile-session.config.json` in the repository root that match the issue-kit names. Merge them with an
   existing file; do not replace its other keys. Derive `workItemPattern` from `branchPattern` and
   `batchBranchPattern` (the first number of the branch, then `^#(\d+)` for commit subjects). The workflow passes the
   lane itself, so `lanePlanGlob` can stay empty. Example for the default patterns and `plans.dir` `docs/plans`:

   ```json
   {
     "baseBranch": "main",
     "workItemPattern": ["^(\\d+)-", "^#(\\d+)"],
     "workItemCommandPattern": "/issue-kit:implement-issues?",
     "lanePlanGlob": "",
     "activityRules": [
       { "pattern": "^Agent:issue-kit:skill-runner|^Skill:issue-kit:(git-commit|open-pr|github-issue)", "category": "ship" },
       { "pattern": "^Agent:issue-kit:build-runner", "category": "build/test" },
       { "pattern": "^Agent:issue-kit:issue-developer", "category": "implement" },
       { "pattern": "^Write:.*docs.plans|^Agent:issue-kit:issue-planner", "category": "plan" }
     ]
   }
   ```

   Add a rule for each project agent of `roles` (for example `^Agent:security-reviewer` → `review`). Write the file
   only after the user confirms.
7. Tell the user what to commit: `issue-kit.config.json`, and the settings and profile files if they changed them.
   Do not commit on your own.
