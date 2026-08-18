# bitdrift Instrumentation Guide

Step-by-step prompts for instrumenting any mobile app with the bitdrift Capture SDK using an AI coding agent. Covers Android, iOS, and React Native. Each prompt drives the **bd-instrumentation** skill to write the call sites, wire the build, and verify it compiles — you run the prompts in order, the skill handles the platform-specific details.

## Files

| File | Audience | Use when |
|------|----------|----------|
| [INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md) | Human | You want to read through the steps, understand what each one does, and paste prompts manually |
| [AGENT_INSTRUMENTATION_GUIDE.md](AGENT_INSTRUMENTATION_GUIDE.md) | Agent | You want a fully autonomous run — point your agent at this file and say *"execute this runbook"* |
| [CLEANUP_GUIDE.md](CLEANUP_GUIDE.md) | Human | You want to remove bitdrift instrumentation and return the app to its baseline state |
| [AGENT_CLEANUP_GUIDE.md](AGENT_CLEANUP_GUIDE.md) | Agent | Autonomous cleanup — the inverse of the agent instrumentation runbook |
| [examples/](examples/) | Human | Real worked examples from running Steps 18–20 against the bitdrift-shop demo app — BDRL scripts, a sample evaluation readout, and the live validation status |

## Prerequisites

Install and authenticate the `bd` CLI:

```bash
brew tap bitdriftlabs/bd && brew install bd
bd auth
```

Install the bitdrift skills:

```bash
npx skills add bitdriftlabs/bd-skills
```

## What gets instrumented

The guide covers SDK init, screen views, user identity, network capture, structured logs, global fields, TTI, spans, device code / support tooling, crash symbolication, log forwarding, and session replay — in an order tuned for fastest time-to-value in a POC. It then hands off to **bd-issue-match** and **bd-cuj** to turn that data into crash workflows, CUJ dashboards, and a criterion-by-criterion evaluation readout.
