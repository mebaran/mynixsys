---
name: repo-kanban-intake
description: Use to turn repo-local request files or high-level feature requests into Hermes Kanban planning tasks with clarification, implementation, review, and PR handoffs.
version: 0.1.0
metadata:
  hermes:
    tags: [kanban, automation, planning, repository]
    related_skills: [one-three-one-rule]
---

# Repo Kanban Intake

This skill converts a user request into a staged Kanban workflow.

## Workflow

1. Read the request and identify target repo, desired outcome, constraints, and
   whether credentials or external systems are involved.
2. If scope is unclear, use `one-three-one-rule` before creating work.
3. Create a planning task first. Pin a domain planning skill when available.
4. Planning output must produce a handoff file in the workspace, not just chat.
5. Planning and architecture tasks must solicit user feedback before any
   implementation task is created.
6. Create review and PR tasks after implementation.

## Kanban Commands

Create a planning task:

```sh
hermes kanban create "Plan: <short title>" \
  --body "<request summary and repo path>" \
  --workspace "dir:<repo path>" \
  --skill one-three-one-rule \
  --skill coder-implementation-plan
```

Create an implementation task after planning:

```sh
hermes kanban create "Implement: <short title>" \
  --parent "<planning-task-id>" \
  --body "Use the plan artifact and keep changes scoped." \
  --workspace "dir:<repo path>" \
  --skill coder-code-implementation
```

Create review and PR task:

```sh
hermes kanban create "Review and PR: <short title>" \
  --parent "<implementation-task-id>" \
  --body "Review changes, address critical findings, and prepare PR." \
  --workspace "dir:<repo path>" \
  --skill coder-codex-review-pr
```

## Watcher

The bundled `scripts/repo_watch.py` polls a directory for Markdown request files
and enqueues planning tasks. Use it as a starting point for a systemd service or
manual daemon.

## Feedback Gate

Planning tasks must end by asking for approval, rejection, or requested changes
using the `one-three-one-rule` structure. Do not create implementation tasks
until the user has approved the plan or explicitly authorized proceeding.
