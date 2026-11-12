# Configuring issue-kit

The plugin works in every repository, but each repository has its own branches, build commands, issue headings and
agents. One JSON file in the repository root, `issue-kit.config.json`, describes them. The skill
`/issue-kit:init-config` drafts that file for you; this page documents every key.

The commit message hook runs only in a repository that has `issue-kit.config.json`. Without the file the workflow
skills use the defaults below.

## Where settings live

Three JSON files, merged key by key; a later file overrides the earlier one:

| Layer | File | Use it for |
|---|---|---|
| 1. defaults | `issue-kit.config.default.json` in the plugin folder | Never edit; copy a key into layer 2 or 3 |
| 2. user | `issue-kit.config.json` in the Claude config folder (`~/.claude/`, or `CLAUDE_CONFIG_DIR`) | Values for all of your repositories, for example `shipLanguage` |
| 3. repository | `issue-kit.config.json` in the repository root | Values that describe this repository; commit this file |

- Every key is optional in layers 2 and 3. A missing file is not an error.
- Objects merge key by key. A text, a list or a true/false value replaces the value of the earlier layer as a whole.
- The defaults file is the schema. An unknown key, a value of another type, an empty value of a required key, an
  invalid regular expression or a pattern without its placeholder stops the skill with a message that names the file
  and the key, for example `issue-kit.config.json: unknown key 'commands.biuld'`.

To see the merged result, run from the repository root:

```bash
pwsh -NoProfile -File "<plugin folder>/scripts/Get-IssueKitConfig.ps1" -Sources
```

`-Key commands.build` prints one value. `/issue-kit:init-config check` runs the same read and also checks paths,
commands, agents and skills.

## Keys

### Branches and text

| Key | Type | Default | Meaning |
|---|---|---|---|
| `baseBranch` | text | `main` | Base branch of issue branches and pull requests. A commit on this branch is a commit not tied to an issue. |
| `branchPattern` | text | `{n}-{slug}` | Name of an issue branch. `{n}` is the issue number, `{slug}` a short kebab-case slug of the English title. Must contain both. |
| `batchBranchPattern` | text | `{first}-{last}-{slug}` | Name of the branch of a batch (`/issue-kit:implement-issues`). Must contain `{first}`, `{last}` and `{slug}`. |
| `shipLanguage` | text | `English` | Language of commit messages, issue comments and pull request text. |

### Build-and-test gate

The `build-runner` agent runs these commands from the repository root. Empty: the agent skips that step and
reports it as `NOT CONFIGURED`; the workflow then names the step as not done.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `commands.build` | text | empty | Full build. Make warnings errors here if the project wants that. |
| `commands.testFull` | text | empty | All tests, after the build. |
| `commands.testProject` | text | empty | Tests of one project or folder; `{project}` is replaced by the name the workflow passes. Must contain `{project}`. |
| `commands.format` | text | empty | Format check that changes nothing (for example a `--check` or `--verify-no-changes` mode). |

### Requirements document and plans

| Key | Type | Default | Meaning |
|---|---|---|---|
| `prd.path` | text | empty | Requirements document, relative to the repository root. Empty: the workflow skips the "requirements document first" step and plans from the issue alone. |
| `prd.idPattern` | text | empty | Regular expression of a requirement id in the document and in issues, for example `REQ-\d+`. Empty: requirement ids are not looked for. |
| `plans.dir` | text | `docs/plans` | Folder of plan files, relative to the repository root. |
| `plans.nameTemplate` | text | `{type}-{n}-{slug}.md` | Name of a plan file. `{type}` comes from `plans.typeLabelPattern`, `{n}` is the issue number, `{slug}` the branch slug. Must contain `{n}`. |
| `plans.language` | text | `English` | Language of the plan text. Identifiers, paths and commands stay as they are. |
| `plans.typeLabelPattern` | text | `^(?:type:)?(bug|feature|chore|test)$` | Regular expression matched against each issue label; the first group of the first match is `{type}`. No match: `feature`. |

### Issues

| Key | Type | Default | Meaning |
|---|---|---|---|
| `issueSections.requirements` | text | `Requirements` | Heading (without `## `) of the issue section that links the requirements document. |
| `issueSections.acceptance` | text | `Acceptance criteria` | Heading of the acceptance section, a `- [ ]` list. The acceptance script also accepts `Acceptance criteria` and `Acceptance`. |
| `issueSections.dependencies` | text | `Dependencies` | Heading of the section that lists blocking issues. |
| `lanes.bug` | list | `["bug"]` | Labels that select the Bug lane. |
| `lanes.testAuthoring` | list | `["type:test"]` | Labels that select the Test-authoring lane. Any other issue takes the Feature lane. |
| `ordering.titleCodePattern` | text | empty | Regular expression of an order code in issue titles. `next-issue` sorts ready issues by its capture groups, compared as numbers, then by issue number; issues without a code go last. Example: `^P(\d+)\.(\d+)` for titles such as `P1.4: Export`. Empty: order by issue number. |

### Roles

A role names the agent (or skill) that does one part of the workflow. The defaults are the plugin agents. A
repository can name its own agent instead, for example one that has the MCP tools of the project in its `tools`
list; plugin agents never list project MCP tools.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `roles.planner` | text | `issue-kit:issue-planner` | Agent that drafts the plan (read-only). |
| `roles.developer` | text | `issue-kit:issue-developer` | Agent that implements the approved plan with tests. |
| `roles.buildRunner` | text | `issue-kit:build-runner` | Agent that runs the build-and-test gate. |
| `roles.skillRunner` | text | `issue-kit:skill-runner` | Agent that carries out one approved commit, issue comment or pull request. |
| `roles.architect` | text | empty | Optional agent that shapes a large or cross-layer change before the plan. Empty: skipped. |
| `roles.securityReviewer` | text | empty | Optional agent that reviews a change that matches `securityReview.triggers`. Empty: skipped. |
| `roles.debugSkill` | text | empty | Optional skill that reproduces and diagnoses a defect in the Bug lane. Empty: the workflow reproduces without it. |
| `roles.testsSkill` | text | empty | Optional skill that picks the test layer and writes tests. Empty: the developer follows `CLAUDE.md` and `.claude/rules/`. |

**Names.** Claude Code puts every plugin component under the plugin name. The `subagent_type` of a plugin agent in
the Agent tool is `<plugin>:<agent>`, for example `issue-kit:issue-planner`. A plugin skill is `<plugin>:<skill>`,
for example `issue-kit:git-commit`, also as a slash command (`/issue-kit:git-commit`). An agent or a skill of the
repository itself (`.claude/agents/`, `.claude/skills/`) has no prefix: `"roles.architect": "architect"`.

### Checks

| Key | Type | Default | Meaning |
|---|---|---|---|
| `securityReview.triggers` | list | empty | Path globs, relative to the repository root. A change that touches a matching file gets the `roles.securityReviewer` review. Empty: no review. |
| `commentReview.globs` | list | empty | Path globs of the files whose added comments the workflow checks for comment hygiene (no change narration, no issue references, no line numbers, no repetition). Empty: no check. |
| `profile.enabled` | true or false | `true` | Profile the session at the commit step. |
| `profile.skill` | text | `harness-kit:profile-session` | Skill that profiles the session. If it is not available in the session, the workflow skips the step with one line. |
| `commitCheck.enabled` | true or false | `true` | Turns on the commit message hook. The hook also needs the repository file `issue-kit.config.json`. |

## Examples

### Example 1: a Node service

Plans in `docs/plans/`, `npm` scripts, issues with English headings, `P<phase>.<n>` codes in titles.

```json
{
  "commands": {
    "build": "npm run build",
    "testFull": "npm test",
    "testProject": "npm test --workspace {project}",
    "format": "npx prettier --check ."
  },
  "ordering": { "titleCodePattern": "^P(\\d+)\\.(\\d+)" },
  "securityReview": { "triggers": ["src/auth/**", "package.json", ".github/workflows/**"] },
  "commentReview": { "globs": ["*.ts", "*.tsx"] }
}
```

### Example 2: a .NET solution with a requirements document

A requirements document with ids `REQ-12`, plans in another language, `develop` as the base branch, issue headings
of the team, its own architect and security reviewer agents in `.claude/agents/`.

```json
{
  "baseBranch": "develop",
  "commands": {
    "build": "dotnet build src/Example.slnx -t:Rebuild -clp:ErrorsOnly",
    "testFull": "dotnet test --solution src/Example.slnx --no-build",
    "testProject": "dotnet test --project src/{project}/{project}.csproj --no-build",
    "format": "dotnet format src/Example.slnx --verify-no-changes"
  },
  "prd": { "path": "docs/requirements.md", "idPattern": "REQ-\\d+" },
  "plans": { "language": "German" },
  "issueSections": { "requirements": "Source", "acceptance": "Acceptance criteria", "dependencies": "Blocked by" },
  "lanes": { "bug": ["bug", "defect"], "testAuthoring": ["tests"] },
  "roles": { "architect": "architect", "securityReviewer": "security-reviewer" },
  "securityReview": { "triggers": ["src/Example.Infrastructure/**", ".github/workflows/**", "src/Directory.Packages.props"] },
  "commentReview": { "globs": ["*.cs", "*.xaml"] }
}
```

### Example 3: the commit check off

A repository that wants the workflow skills but its own commit format:

```json
{
  "commitCheck": { "enabled": false }
}
```
