---
name: git-push
description: Use when committing and pushing completed work to the agent's assigned Git repository. Handles per-repo commit, checks, push, and result reporting.
---

# Git Push

Commit and push completed work to the agent's assigned Git repository.

## Rules

- Identify the current repository before making Git changes.
- Treat `frontend`, `middle-end`, and `backend` as separate repositories.
- Review the changed files before committing.
- Run relevant checks/tests before pushing when available.
- Create a clear, concise commit message describing the change.
- Commit only the work belonging to the current task.
- Push the commit to the configured remote and branch.
- Report the repository, branch, commit hash, and push result.
- Stop and report an error if the repository, remote, branch, or push state is unclear.

## Scope Limits

Do not handle project planning, implementation, review, or PR workflows. Those belong to other skills.
