---
name: review-project
description: Use when performing an evidence-based review of a completed project across requirements, frontend middle-end backend integration, API contracts, database, security, bugs, quality, and build tests. Returns PASS or FAIL with evidence.
---

# Review Project

Perform an evidence-based review of the completed project. Do not guess. Do not fix issues unless explicitly instructed.

## Review

- Requirements and expected behavior
- Frontend → Middle-end integration
- Middle-end → Backend integration
- API contracts
- Database/data handling
- Security issues
- Errors, bugs, and missing functionality
- Code quality and maintainability
- Build and relevant tests

## Rules

- Inspect the actual code and run relevant checks; do not guess.
- Every finding must include evidence such as a file, location, test result, or observed behavior.
- Separate critical, high, medium, and low findings.
- Do not mark PASS while critical or high-severity issues remain.
- PASS only when the required functionality and integrations are verified.
- FAIL when required functionality is missing, broken, or insufficiently verified.
- Do not fix issues unless explicitly instructed.

## Output

Return a concise structured result:

```text
status: PASS | FAIL
requirements: verified/unverified
tests: results
integration: verified/unverified
findings: []
evidence: []
```

A PASS must contain enough evidence for the Orchestrator to confidently use it as the completion gate.
