---
name: one-three-one-rule
description: Use for decisions with multiple viable approaches; present one problem, three options with tradeoffs, and one recommendation before asking for user feedback.
version: 0.1.0
metadata:
  hermes:
    tags: [communication, decision-making, planning, tradeoffs]
    related_skills: []
---

# One Three One Rule

Use this skill when a task involves a meaningful decision, tradeoff, or
architecture choice and the user has not already chosen the approach.

## Format

1. Problem: one concise sentence describing the decision or outcome.
2. Options: exactly three distinct viable approaches. Label them A, B, and C.
   Include the main pros and cons for each option.
3. Recommendation: choose one option and explain why it best fits the user's
   context.
4. Definition of Done: list concrete success criteria for the recommended
   option.
5. Implementation Plan: list the concrete steps needed to execute the
   recommendation.

## Feedback Gate

End by asking the user to approve the recommendation, choose a different option,
or request changes. Do not treat the decision as approved until the user
responds, unless they have explicitly delegated that category of decision.
