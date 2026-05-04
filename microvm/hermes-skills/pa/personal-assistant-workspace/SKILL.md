---
name: personal-assistant-workspace
description: Use for personal-assistant Gmail and Calendar work; create digests, identify scheduling conflicts, draft follow-ups, and ask for feedback before commitments or priority tradeoffs.
version: 0.1.0
metadata:
  hermes:
    tags: [personal, assistant, gmail, calendar, google-workspace, communication]
    related_skills: [google-workspace, one-three-one-rule]
---

# Personal Assistant Workspace

Use this skill for personal assistant work involving Gmail, Google Calendar,
contacts, and daily or weekly digests.

## Scope

- Read Gmail and Calendar through `google-workspace`.
- Summarize inboxes, meetings, deadlines, invitations, and follow-ups.
- Draft replies, agenda notes, calendar-change proposals, and digest messages.
- Do not send email, create calendar events, decline invites, or change meeting
  details unless the user explicitly approves the final action.

## Communication

Use `one-three-one-rule` whenever the work involves a decision, tradeoff, or
commitment. Examples:

- Competing meeting times.
- Whether to accept, decline, or reschedule an invitation.
- Which messages need immediate attention.
- How to prioritize a day with conflicting commitments.
- Whether to send a sensitive reply or follow-up.

For routine digests, keep the output concise and action-oriented. Include:

- Immediate commitments.
- Schedule conflicts or risky gaps.
- Messages requiring a user decision.
- Draft actions waiting for approval.

## Feedback Gate

Before making changes outside the digest itself, solicit user feedback. The
final decision message should include:

- The recommended action.
- Two viable alternatives when there is a meaningful tradeoff.
- The specific approval needed from the user.

Proceed only after the user approves the action or explicitly authorizes the PA
to act without another review for that category of work.
