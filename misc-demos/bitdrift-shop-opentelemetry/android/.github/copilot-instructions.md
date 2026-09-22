# Copilot Instructions

Project-level instructions for GitHub Copilot in this repository.

## How to Handle bitdrift Requests

- For bitdrift setup, instrumentation, workflows, or investigations, route through the bitdrift skills entrypoint: `$bd`.
- If skills are not installed, follow `.skills/public/agent-setup.md` exactly, then continue with `$bd-setup`.

## Strict Skills Mode (Opt-In)

- Trigger strict mode when the user explicitly asks for skills-only behavior (for example: "strict skills mode", "use the investigation skill", "follow skills exactly").
- In strict mode, route through `$bd` first, then use the matching skill (`$bd-platform` for investigations).
- For investigations, if `.skills/internal/skills/bd-platform/investigation.md` exists, follow it step-by-step and do not skip required steps.
- Use commands exactly as documented by the active skill; do not substitute alternate commands unless the user asks.
- If any strict-mode command fails, stop and report the exact failing command and blocker before continuing.
- If skills are missing, follow `.skills/public/agent-setup.md` exactly, then resume strict mode.

## Working Style

- Stay scoped to the user request; avoid broad repo scans unless needed.
- Execute in small, ordered steps and validate after meaningful edits.
- Use exact commands when the guide specifies them; do not rewrite flags unless requested.
- If blocked by auth/sandbox/permissions, report the block and ask for approval.

## Command and Data Conventions

- Prefer `bd` CLI commands before raw API calls.
- Prefer `bd ... -o json|jsonl --jq '<filter>'` for direct filtering.
- Use external `jq` for cached JSON or advanced filters; avoid Python for simple parsing.
- Preserve SDK API casing (for example `Logger.logInfo`) and use `snake_case` for workflow/CLI fields.

## Safety

- Never commit secrets, keys, tokens, or private endpoints.
- Treat `.skills/internal/` as internal context.
- Keep examples production-safe and repository-relevant.
