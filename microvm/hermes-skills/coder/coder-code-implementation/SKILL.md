---
name: coder-code-implementation
description: Use for implementing approved repository plans with focused code edits, tests, and Kanban handoff summaries.
version: 0.1.0
metadata:
  hermes:
    tags: [coder, implementation, coding, tests]
    related_skills: [coder-implementation-plan, systematic-debugging, test-driven-development]
---

# Coder Code Implementation

Use this skill for implementation tasks after a plan exists.

## Process

1. Read the plan artifact first.
2. Keep changes scoped to the approved plan.
3. Prefer existing repo patterns and commands.
4. Run focused tests or static checks when available.
5. If requirements are ambiguous, block the Kanban task instead of guessing.
6. Leave a handoff summary with changed files, tests run, and residual risk.

## Constraints

- Do not create or push a PR from an implementation task unless explicitly
  assigned that responsibility.
- Do not broaden repo auth or Google Workspace access.
- Do not modify unrelated repositories in the shared workspace.

## Completion Summary

When completing Kanban, include:

- Files changed
- Tests/checks run
- Any skipped verification
- Suggested review focus
