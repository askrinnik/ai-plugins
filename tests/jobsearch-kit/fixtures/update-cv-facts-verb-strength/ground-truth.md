Ground truth: update-cv-facts with the fact "At Example Payments Ltd I have used Redis in production since 2022 as a
cache for the payment API, which cut the p95 response time from 300 ms to 120 ms. It may go into CVs."
Regression of 2026-10-22: the first run wrote "Introduced Redis".

Max score: 4

- Item 1: The new CV bullet keeps the verb of the fact ("use" or "used"); it does not say introduced, led, built, designed or anything stronger.
- Item 2: The bullet keeps the facts: Redis as a cache for the payment API, p95 from 300 ms to 120 ms.
- Item 3: The fact in candidate_facts.md keeps the user's wording and adds a date; it adds no detail the user did not give (no team size, no role, no other numbers).
- Item 4: The answer shows or describes the change of the full CV and names the files that changed.
