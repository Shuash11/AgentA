---
name: orchestrator-configure-subagents
description: Use ONLY when Build Agent initializes a new project to bootstrap orchestrator, frontend, middle-end, backend, reviewer model, provider, variant config. Executed by Build Agent, never by Orchestrator.
---

# Orchestrator Configure Subagents

Bootstrap configuration skill executed exclusively by the Build Agent when initializing a new project. Configures the agent system for the Orchestrator to consume. The Orchestrator must never run this skill and must never initialize or generate its own configuration.

## Executor

- Executor: Build Agent only.
- Trigger: new project initialization by the Build Agent.
- If `.opencode/orchestrator-subagents.json` exists and is complete, the Build Agent confirms reuse or reconfiguration. Otherwise the Build Agent runs full configuration before any other work.

## Agents

Configure these 5 agents, each with independent `model`, `provider`, `variant`. Do not hard-code values.

- `orchestrator` — coordinates and delegates work.
- `frontend` — owns the frontend repository.
- `middle_end` — handles validation, authentication/authorization, and request/response processing between frontend and backend; owns the middle-end repository.
- `backend` — owns backend logic, services, and data operations.
- `reviewer` — reviews work across all repositories.

## Process

The Build Agent asks the user for each agent individually, in order orchestrator, frontend, middle_end, backend, reviewer, via the `question` tool:

1. **Model** — Which model should this agent use?
2. **Provider** — Which provider should supply that model?
3. **Variant** — Which variant/configuration should be used?

Rules:

- Five independent configurations.
- Do not hard-code, suggest, or default model names, providers, or variants. Accept user-supplied values verbatim.
- Do not reuse one agent's answers for another unless the user explicitly says so.
- Free-text answers allowed. If the project defines choices in `opencode.json`, `opencode.jsonc`, or `.opencode/`, you may surface those as options, but never invent options.

## Output

Save the completed configuration to `.opencode/orchestrator-subagents.json`. Create `.opencode/` if missing. Overwrite only after explicit user confirmation when a config already exists.

Required shape:

```json
{"orchestrator":{"model":"...","provider":"...","variant":"..."},"frontend":{"model":"...","provider":"...","variant":"..."},"middle_end":{"model":"...","provider":"...","variant":"..."},"backend":{"model":"...","provider":"...","variant":"..."},"reviewer":{"model":"...","provider":"...","variant":"..."}}
```

## Completion Check

Before finishing, the Build Agent verifies all 5 entries are present and each has non-empty `model`, `provider`, and `variant`. Do not finish with missing or incomplete entries.

## Scope Limits

Strictly a configuration/bootstrap skill executed by the Build Agent. Do not add orchestration, planning, delegation, coding, review, or repository workflow logic. The Orchestrator is never responsible for running this skill or for initializing its own configuration.
