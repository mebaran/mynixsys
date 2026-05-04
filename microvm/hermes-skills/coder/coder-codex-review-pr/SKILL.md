---
name: coder-codex-review-pr
description: Use for Codex-powered review and PR preparation after implementation tasks; prioritize findings, tests, and a clean draft PR.
version: 0.1.0
metadata:
  hermes:
    tags: [coder, codex, review, pull-request, github]
    related_skills: [github-auth, github-pr-workflow, github-code-review]
---

# Coder Codex Review And PR

Use this skill after implementation work is complete.

## Review Stance

1. Lead with bugs, regressions, security/data-access risks, and missing tests.
2. Use file and line references where possible.
3. Separate must-fix findings from follow-up suggestions.
4. If critical issues exist, create follow-up implementation tasks instead of
   opening a ready PR.

## PR Preparation

1. Confirm `gh auth status` works.
2. Check `git status` and do not include unrelated changes.
3. Run or summarize relevant tests.
4. Prepare a draft PR unless the user asked for ready-for-review.
5. Include the Kanban task IDs and plan artifact in the PR body.

## Completion Summary

Include:

- Review findings
- Tests/checks
- PR URL or reason no PR was opened
- Follow-up Kanban tasks created
