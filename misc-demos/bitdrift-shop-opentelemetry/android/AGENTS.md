# Agent Instructions (Project Root)

This file defines the default guidance for AI coding agents working in this repository.

## Scope

- Use this file as the project-level source of truth for agent behavior.
- For bitdrift setup/playbooks, prefer the installed bitdrift skills (entrypoint: `$bd`).
- Keep changes focused on the user's request; do not run broad repo exploration unless needed.

## bitdrift Routing

- If the user asks about bitdrift setup, instrumentation, workflows, charts, or investigations, start with `$bd`.
- If skills are not available yet, follow `.skills/public/agent-setup.md` to install them, then continue via `$bd-setup`.

## Strict Skills Mode (Opt-In)

- Trigger strict mode when the user explicitly asks for skills-only behavior (for example: "strict skills mode", "use the investigation skill", "follow skills exactly").
- In strict mode, route through `$bd` first, then use the matching skill (`$bd-platform` for investigations).
- For investigations, if `.skills/internal/skills/bd-platform/investigation.md` exists, follow it step-by-step and do not skip required steps.
- Use commands exactly as documented by the active skill; do not substitute alternate commands unless the user asks.
- If any strict-mode command fails, stop and report the exact failing command and blocker before continuing.
- If skills are missing, follow `.skills/public/agent-setup.md` exactly, then resume strict mode.

## Execution Rules

- Follow requested steps in order. Do not reorder unless the user asks.
- Minimize upfront discovery. Gather only context needed for the current step.
- Run commands yourself unless a step explicitly requires user input.
- Pause only when permissions, auth, sandbox rules, or explicit user action is required.

## Command Fidelity

- When a guide provides an exact command, run it exactly as written.
- Do not add/remove/reorder flags unless the user explicitly asks.
- If a command is blocked by environment limits, report the block instead of rewriting it.
- If deviation is necessary, explain why and ask before proceeding.

## Conventions

- Prefer `bd` CLI commands before raw API calls or custom scripts.
- Instrumentation guidance is about app code and SDK usage.
- Platform guidance is about bitdrift workflows, sessions, timelines, and issues.
- Use real API names in examples (for example `Logger.start`, `Logger.logInfo`, `bd tail`, `bd auth`).
- Prefer `snake_case` for workflow/CLI field names; preserve SDK-native casing for method names.

## CLI Output Filtering

- Prefer `bd ... -o json|jsonl --jq '<filter>'` for direct filtering of one `bd` command.
- Add `-r` when the result is consumed as a raw shell value (for example IDs).
- Use external `jq` for cached files/variables or features not covered by `--jq`.
- Do not use Python for parsing `bd` output when `--jq` or `jq` is sufficient.

## Safety and Content Boundaries

- Do not introduce secrets, keys, tokens, or internal-only endpoints in committed files.
- Treat `.skills/internal/` as internal context; do not copy private-only details into user-facing outputs.
- Keep guidance focused on runtime use, not skills-repo maintenance workflow details.
