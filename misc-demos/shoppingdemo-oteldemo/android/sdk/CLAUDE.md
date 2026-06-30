# Claude Instructions (Project Root)

This file mirrors `AGENTS.md` so Claude-style tooling can auto-load the same project guidance.

## Scope

- Follow `AGENTS.md` as the canonical project instruction set.
- Use this file for compatibility with tools that auto-read `CLAUDE.md`.

## Core Rules

- Use `$bd` as the first routing step for bitdrift setup, instrumentation, workflows, and investigations.
- Keep execution stepwise and targeted; avoid broad discovery unless required.
- Run exact setup commands as documented; do not rewrite flags unless requested.
- If sandbox/auth/permissions block a command, report the block and request approval.
- Prefer `bd` CLI + `--jq`/`jq` for data extraction over custom parsers.

## Strict Skills Mode (Opt-In)

- Trigger strict mode when the user explicitly asks for skills-only behavior (for example: "strict skills mode", "use the investigation skill", "follow skills exactly").
- In strict mode, route through `$bd` first, then use the matching skill (`$bd-platform` for investigations).
- For investigations, if `.skills/internal/skills/bd-platform/investigation.md` exists, follow it step-by-step and do not skip required steps.
- Use commands exactly as documented by the active skill; do not substitute alternate commands unless the user asks.
- If any strict-mode command fails, stop and report the exact failing command and blocker before continuing.
- If skills are missing, follow `.skills/public/agent-setup.md` exactly, then resume strict mode.

## Safety

- Never expose secrets, tokens, or private endpoints.
- Do not copy internal-only `.skills/internal/` content into public guidance.
- Keep outputs focused on the user task and repository context.
