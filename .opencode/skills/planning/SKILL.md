---
name: planning
description: Use when creating a clear implementation plan before work begins. Breaks requirements into tasks with owners, dependencies, contracts, and expected results.
---

# Planning

Create a clear implementation plan before work begins.

## Process

1. Understand the requirements and expected outcome.
2. Identify the required work and break it into concrete tasks.
3. Identify dependencies between Frontend, Middle-end, Backend, and Reviewer work.
4. Determine which agent owns each task.
5. Identify required API contracts, data models, integrations, and constraints.
6. Produce an ordered plan based on dependencies, while allowing independent tasks to proceed in parallel.
7. Make the plan specific enough for the Orchestrator to delegate without ambiguity.

## Rules

- Do not implement the work.
- Do not invent missing requirements.
- Keep the plan practical and concise.
- Record important assumptions or unresolved requirements.

## Output

Output a clear task plan containing:
`task`, `agent`, `dependencies`, `expected result`.

Keep detailed implementation procedures out of this skill.
