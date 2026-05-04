---
name: coder-implementation-plan
description: Use for repository planning tasks before code edits; produce concise implementation plans, clarify blockers, and create handoff artifacts for implementation agents.
version: 0.1.0
metadata:
  hermes:
    tags: [coder, planning, github, kanban]
    related_skills: [repo-kanban-intake, one-three-one-rule]
---

# Coder Implementation Plan

Use this skill for planning repository work before code changes.

## Scope

Primary repositories are intentionally not baked into this skill. Resolve the
target repository from the Kanban task, explicit user request, or the current
workspace path.

## Process

1. Inspect the target repository enough to identify the relevant modules,
   tests, commands, and risk.
2. Use `one-three-one-rule` for missing business or product decisions.
3. Write a plan artifact under `.hermes/plans/`.
4. The plan must include files likely to change, test commands, rollout risk,
   and review checklist.
5. Present the plan to the user and ask for feedback before implementation.
6. Do not edit production code in planning tasks unless explicitly asked.

## Handoff File

Create:

```text
.hermes/plans/<task-id-or-slug>.md
```

Required sections:

- Goal
- Assumptions
- Proposed changes
- Files/modules
- Tests
- Risks
- Review checklist

## Feedback Gate

Every planning or architecture task must solicit user feedback before it is
completed. The final comment/message should include:

- The recommended approach.
- The strongest alternative.
- The specific decision needed from the user.

Do not create implementation tasks until the user approves the plan or explicitly
authorizes proceeding without another review.
