# Context budget

Every model call reads the whole conversation again, so the cost is roughly calls × context size. In measured runs
of this workflow most of the spend was cache reads of a context that only grew. These rules keep the context small.
They apply to every step of `implement-issue` and `implement-issues`.

1. **Compact at milestones.** You cannot run slash commands yourself. At each milestone, give the user the
   ready-to-paste `/compact` command below. Continue when the user has run it or told you to go on without it.
   Whatever a later step needs must already be on disk or in the focus text.
   - **After the plan is approved and saved (end of step 7):**
     `/compact keep: issue number and exact title, lane, acceptance list, plan file path, decisions made during plan review, complexity`
   - **After build and tests pass (end of step 9):**
     `/compact keep: issue number and exact title, lane, acceptance list, plan file path, list of changed files, build and test results`
   - **After the user confirms the result (end of step 11):**
     `/compact keep: issue number and exact title, lane, branch, git diff --stat, one line per changed file, acceptance table with results, verification summary`
   - Skip a milestone when the conversation up to it is still short (under about 40 tool calls).
2. **Runaway guard.** If one turn passes about 100 tool calls without a milestone (repeated build-and-fix loops),
   stop at the next natural pause and offer `/compact` with a focus text of the same kind. Never let a single turn
   run past about 150 tool calls.
3. **One issue per session.** After step 14, recommend a new session for the next issue instead of continuing in
   this one.
4. **Read narrowly.** Search first, then read around the match. Read a whole file only when you change most of it or
   it is under about 200 lines. Never read again a file you just edited. Read only the sections of the requirements
   document that the issue links. For broad exploration use the `Explore` agent and ask for a summary of at most 30
   lines.
5. **Keep tool output small at the source.** Builds report errors only; test output goes to a file, and you read
   only the summary and the first failures; `git diff --stat` before a full diff, then per file;
   `gh … --json <fields> --jq …`.
6. **Delegate noisy work** to the agents of the *Delegation* table, so that their raw output stays out of this
   conversation.
7. **Scratch paths stay outside the repository.** Every scratch folder or file that you give to the build runner or
   the skill runner lies in your session's scratch folder (or, without one, the system temp folder), never under the
   repository root. Files there show up in `git status`, can be staged by mistake, and the `rm -rf` to clean them up
   is often denied. Give a full path to the file or folder, not a hint such as "the system temp folder", and write it
   with forward slashes (`C:/Users/…/scratchpad/commit.txt`): the agents run commands in Bash, where a backslash is an
   escape character.
