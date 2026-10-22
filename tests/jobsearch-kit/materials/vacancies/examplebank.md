# Vacancy: ExampleBank (fictional)

Used in the headless check of 2026-10-22 (adapt-cv → cover-letter → submit-application in one run). Expected: Go and
Kubernetes are named as gaps; Redis appears only at the strength of the confirmed fact; the form question "How did
you hear about us?" stays open because its default answer has `status: ask`.

## Text given to the skill

```
Senior Backend Engineer (Java), Payments Platform, ExampleBank, Lisbon (hybrid, 2 days in office). We build the card payments platform that serves 3 million customers. Requirements: 7+ years of Java, Spring Boot, PostgreSQL, Kafka or another event streaming platform, experience with high-load REST APIs, mentoring. Nice to have: Kubernetes, Go, Redis. We offer: salary 4500-6000 EUR gross per month, hybrid work, learning budget. EU work permit required. Apply with a CV and a cover letter.
```

## Form questions used with submit-application

- Salary expectations (EUR, monthly gross)
- Earliest start date
- Do you need a work permit?
- Why do you want to join ExampleBank? (free text, up to 100 words)
- How did you hear about us?

## Fact given to update-cv-facts before this run

"At Example Payments Ltd Jordan has used Redis in production since 2022 as a cache for the payment API, which cut the
p95 response time from 300 ms to 120 ms. It may go into CVs." The first run wrote "Introduced Redis"; the verb
must stay "used" (regression found on 2026-10-22).
