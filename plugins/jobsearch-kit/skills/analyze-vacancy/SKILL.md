---
name: analyze-vacancy
description: Analyze a job vacancy end to end. Use when the user shares a vacancy link (or text) and asks to analyze it, check the fit, research the company, or prepare an application. Builds the skill-match table, researches the company and its people, then hands over to adapt-cv (tailored CV), cover-letter and submit-application.
---

# Analyze a vacancy

Before the first step, read `${CLAUDE_SKILL_DIR}/../../reference/workspace.md` (workspace layout, settings and
precedence) and `${CLAUDE_SKILL_DIR}/../../reference/rules.md` (core rules, documents, style). Then read the
workspace `CLAUDE.md`: it overrides the plugin defaults. Run every command from the workspace root.

Use the conversation language, the notes language (vacancy, fit analysis, company research, work log) and the
documents language (CV, cover letter) from the workspace settings. Never invent experience: the only sources are
`MyProfile/candidate_facts.md` and `MyProfile/cv/cv_master.yaml`.

The skill has two stages with one stop between them:

1. **Fit table and company research** (steps 1–4), then stop and wait for the user's decision.
2. **Application documents** (steps 5–6), only after the user says to continue.

## 1. Read the vacancy

- Open the link in the built-in browser (`navigate`, then `get_page_text`). If the page needs a sign-in (LinkedIn
  Jobs and the like), ask the user to sign in in the built-in browser and wait; never type credentials yourself.
- Check `applications.md` and the existing folders for earlier applications to the same company and mention them.
- Create `YYYY_MM_DD_<Company>/` (today's date) and write `vacancy.md` in the notes language: source link and date
  read, who found the vacancy (ask if unknown), company and legal entity, title, location, work model, salary,
  responsibilities, requirements, nice to have, what they offer, eligibility rules (citizenship, work permit,
  language, relocation), and what matters but is not said in the vacancy (filled in after step 3).

## 2. Fit table

- Read `MyProfile/candidate_facts.md` and `MyProfile/cv/cv_master.yaml` (the single source of CV text).
- Write `fit-analysis.md` in the notes language:
  - separate tables for required items, nice-to-have items and hidden requirements (found in step 3);
  - columns: requirement, status (✅ confirmed / 🟡 partial / ❌ missing / ❓ not in the facts, question to the
    user), evidence or comment; after the user answers, replace each ❓ with one of the other statuses;
  - a summary: fit estimate in percent, the strongest matches, the main risks and gaps, eligibility risks.
- Show all the tables and the summary in the chat.
- Ask targeted questions **only** about requirements that `candidate_facts.md` does not cover. Never fill a gap by
  guessing. Record each confirmed answer with the `jobsearch-kit:update-cv-facts` skill, then update the table.

## 3. Research the company

Write to `_Companies/<Company>/README.md` (the company's permanent folder, shared by all its vacancies),
in the notes language. If the folder exists, update it and keep what is there; mark each new section with its date.
Give a source and the source date for every fact. Use these sections in this order; skip a section only if you
found nothing for it: short summary with pros and cons, company, registry and finances, salaries, real stack,
people, LinkedIn, news and reviews, questions worth asking, sources.

- **Company:** what it does, products, clients, offices, history, owners.
- **Registry and finances:** legal entity, registration code, revenue, profit, headcount by year, owners and board.
  Use the official business register of the entity's country and aggregators of public financial or tax data.
- **Salaries:** the vacancy range, the average salary from public tax or registry data where it exists, public
  salary data (Glassdoor, levels.fyi and similar). Compare with the user's expectations if they are known.
- **News and reviews:** news for the last 12–18 months, funding, layoffs, employee reviews.
- **Real stack:** the company's other vacancies, engineering blog, GitHub, conference talks. Look for hidden
  requirements (for example, the backend is in a language the vacancy does not name) and add them to
  `fit-analysis.md`.
- **People:**
  - people named in the vacancy (recruiter, hiring manager, contact person);
  - leadership: CEO, CTO, VP or Head of Engineering;
  - the future team: engineers and team leads in the relevant office or team, their background and languages;
  - mutual connections: former colleagues or contacts of the user who work there (possible referral).
- **LinkedIn:** people and the company page are much easier to research when signed in. When you need it, ask the
  user to sign in to LinkedIn in the built-in browser and wait. Read only: never send connection requests, messages,
  likes or follows, and never change anything in the account. Mark the section as gathered with sign-in, read only,
  with the date.
- End with a short list of pros and cons and questions worth asking the company.

## 4. Stop and report

- Add a row to `applications.md` with the status "not submitted" (in the notes language), the fit percentage and a
  short comment (who shared the link, whether it is a referral; ask if unknown).
- Report to the user: fit percentage, strongest matches, main risks, the key company findings, and links to
  `fit-analysis.md` and `_Companies/<Company>/README.md`.
- Ask whether to continue with the CV or defer. **Wait for the answer.** If the user defers, record the reason in
  `applications.md` and go to step 6.

## 5. Application documents

- **CV:** invoke the `jobsearch-kit:adapt-cv` skill with the Skill tool and give it the application folder. The gap analysis is
  already in `fit-analysis.md`. `jobsearch-kit:adapt-cv` shows only the CV proposals, waits for the user to confirm them, and then
  builds the CV.
- **Cover letter:** if the vacancy or the application form asks for one (a required field, "send a cover letter",
  a motivation question), make it without asking. Otherwise ask whether one is needed. To make it, invoke the
  `jobsearch-kit:cover-letter` skill with the Skill tool and give it the application folder. This skill writes the log, so the
  `jobsearch-kit:cover-letter` skill must not write it.
- **Form questions and submission:** when the user is ready to submit, invoke the `jobsearch-kit:submit-application` skill. It
  drafts the form answers (salary, notice period, motivation) from `MyProfile/application_defaults.yaml` and the
  facts, checks the PDFs and later records the submission.

## 6. Log

- Add a work log entry to `README.md` in the notes language: vacancy link, fit percentage, status (analyzed,
  deferred, or CV prepared until the user says it was submitted), files created and open follow-ups.
- Update the `applications.md` row.
- Do not commit. Offer the commit to the user at the end and commit only if they say so. Never push.
