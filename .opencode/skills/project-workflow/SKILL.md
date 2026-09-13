---
name: project-workflow
description: Use when executing a multi-agent project to orchestrate plan dependencies, delegation, reviewer PASS gate, and fix-review cycles. Orchestrator workflow control only.
---

# Project Workflow

Define the execution flow for the multi-agent project. Focused only on workflow orchestration. Agent behavior belongs to agent prompts and detailed procedures belong to their respective skills.

## Workflow

1. Read the project plan and identify dependencies.
2. Delegate each task to the appropriate agent with the required context.
3. Allow independent tasks to run without unnecessary sequencing.
4. Wait for required dependencies before delegating dependent tasks.
5. When all required implementation work is complete, delegate the integrated project to the Reviewer.
6. The Reviewer checks the implementation against the plan, requirements, integrations, and relevant quality criteria.
7. If the Reviewer returns `PASS` with sufficient evidence, the workflow is complete.
8. If the Reviewer returns `FAIL`, delegate each finding to the appropriate agent for correction.
9. After corrections, invoke the Reviewer again.
10. Repeat the fix → review cycle until `PASS`.

## Rules

- Do not perform a full review after every individual agent finishes.
- Do not enforce a fixed Frontend → Middle-end → Backend order; follow actual dependencies.
- Do not declare completion without Reviewer `PASS`.
- Escalate repeated unresolved failures instead of looping indefinitely.
