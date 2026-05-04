# Task Model Routing Notes

Hermes supports:

- A default profile model in `config.yaml` under `model`.
- A single default delegation model under `delegation`.
- Per-session model selection through Hermes CLI/TUI commands.
- Per-task toolset narrowing for `delegate_task`.

Hermes 0.12.0 does not expose a `model` field on `delegate_task` tasks. That
means this desired workflow is not fully declarative yet:

1. Use Codex to create implementation plans.
2. Use MiniMax to perform code edits.
3. Use Codex to review the result.

Recommended operational pattern for now:

1. Start a planning session with a Codex model/provider and ask for an
   implementation plan only.
2. Start an execution session with a MiniMax model/provider and give it the
   approved plan.
3. Start a review session with Codex and ask for review findings only.

For repeatable automation, add a custom Hermes skill or small wrapper later
that shells out to separate `hermes chat --provider ... --model ...` commands
for each phase. That wrapper should write the plan/review artifacts into the
profile workspace so each step has explicit handoff files.

