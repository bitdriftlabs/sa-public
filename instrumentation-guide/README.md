# bitdrift Instrumentation Guide

Step-by-step prompts for instrumenting any mobile app with the bitdrift Capture SDK using an AI coding agent. Covers Android, iOS, and React Native. Each prompt drives the **bd-instrumentation** skill to write the call sites, wire the build, and verify it compiles — you run the prompts in order, the skill handles the platform-specific details.

**v1.3** is reviewed against Capture SDK 0.23.12 — notably, session replay is **on by default**, so Step 17 confirms or disables it rather than enabling it.

**v1.2** pairs screen views with spans: the same journey elements that become Sankey nodes and funnel steps also get duration spans, so a POC ends with per-step latency percentiles and not just conversion.

## Files

| File | Audience | Use when |
|------|----------|----------|
| [INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md) | Human | You want to read through the steps, understand what each one does, and paste prompts manually |
| [AGENT_INSTRUMENTATION_GUIDE.md](AGENT_INSTRUMENTATION_GUIDE.md) | Agent | You want a fully autonomous run — point your agent at this file and say *"execute this runbook"* |
| [CLEANUP_GUIDE.md](CLEANUP_GUIDE.md) | Human | You want to remove bitdrift instrumentation and return the app to its baseline state |
| [AGENT_CLEANUP_GUIDE.md](AGENT_CLEANUP_GUIDE.md) | Agent | Autonomous cleanup — the inverse of the agent instrumentation runbook |
| [examples/](examples/) | Human | Real worked examples from running this guide against the bitdrift-shop demo app — BDRL scripts, a sample evaluation readout, funnel pitfalls, and the journey-span traps |

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

The guide covers SDK init, screen views, user identity, network capture, structured logs, global fields, TTI and the cold-start span waterfall, spans for every journey element, device code / support tooling, crash symbolication, log forwarding, and session replay — in an order tuned for fastest time-to-value in a POC. It then hands off to **bd-cli** and **bd-cuj** to turn that data into crash workflows, CUJ dashboards, and a criterion-by-criterion evaluation readout.
