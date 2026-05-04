---
name: kanban-orchestrator-workspace
description: Use for turning user requests into Kanban tasks, routing work to specialist Hermes profiles, and tracking task handoffs.
version: 0.1.0
metadata:
  hermes:
    tags: [orchestrator, kanban, routing, planning]
    related_skills: [repo-kanban-intake, one-three-one-rule]
---

# Kanban Orchestrator Workspace

Use this skill from the shared orchestrator profile. The orchestrator owns the
shared Kanban board at `$HERMES_HOME/kanban.db` and routes work to named worker
profiles such as `coder` and `pa`.

## Routing

- Assign repository planning, implementation, test, and PR work to `coder`.
- Assign Gmail, Calendar, digest, and personal follow-up work to `pa`.
- Keep ambiguous requests in triage until the target profile, workspace, and
  acceptance criteria are clear.

## Process

1. Clarify the desired outcome, constraints, target workspace, and assignee.
2. Create a Kanban task with a concrete title and enough body context for a
   worker to proceed without rereading the chat.
3. Use parent-child task links for staged work such as plan, implement, review.
4. Subscribe the user to task notifications when the request came from a
   messaging gateway.
5. Summarize task IDs, assignees, and what will happen next.

## Defaults

Use `--workspace scratch` for general PA or research tasks. For code tasks,
prefer `--workspace dir:/var/lib/hermes/profiles/coder/workspace/repos/<repo>`
when the target repo already exists.
