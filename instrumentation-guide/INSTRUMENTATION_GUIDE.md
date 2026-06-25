# bitdrift Instrumentation Guide

**Version 1.0**

A platform-neutral, step-by-step guide for instrumenting **any** mobile app with the bitdrift Capture SDK — **by prompting an AI coding agent**. Each step is a ready-to-use prompt that drives the **bd-instrumentation** skill to do the actual work (write the call sites, wire the build, verify it compiles). You don't write the code; you run the prompts in order and the skill handles the platform-specific details on Android, iOS, or React Native.

Each step also lists the bitdrift feature it **unlocks** and the relevant **docs**, so you know what each prompt buys you.

The order is tuned for a proof-of-concept: stand up the SDK (1–3), then light up the timeline with the highest-value signals first — screen views, user identity, and network (4–6) — before layering on logs, performance, and operational features. This follows bitdrift's [Integration first steps](https://docs.bitdrift.io/product/first-steps). The categories are independent, so run only the prompts you need, in any order that suits your app.

> **The prompts are platform-neutral.** Run the same prompt whether the target is Android, iOS, or React Native — the skill detects the platform and applies the right APIs. See [Platform notes](#platform-notes) at the bottom for per-platform specifics the skill handles for you.

---

## Setup — install the skills first

These prompts assume your agent (Claude Code, Cursor, Codex, Copilot, or any skills-compatible agent) has bitdrift's skills installed:

- **bd-instrumentation** — installs and instruments the Capture SDK; detects the platform and whether the SDK is already present, then does a fresh install or extends an existing integration. This is the skill every prompt below drives.
- **bd-docs** — fetches live bitdrift documentation at query time.
- **bd-cli** — drives the `bd` CLI for symbol/source-map uploads, workflows, and key management.

Install and authenticate the `bd` CLI (macOS, Homebrew):

```bash
brew tap bitdriftlabs/bd
brew install bd
bd auth   # browser login; for CI/automation use --api-key <key> or the BD_API_KEY env var
```

Then install the skills with [skills.sh](https://skills.sh/) (requires `node`/`npm`):

```bash
npx skills add bitdriftlabs/bd-skills
# update later with: npx skills update --all
```

The skills follow the [agentskills.io](https://agentskills.io/) open standard. See the [CLI Quickstart](https://docs.bitdrift.io/cli/quickstart) and [Agent Skills docs](https://docs.bitdrift.io/product/skills/overview).

If you have the cli and skills installed make sure to update them both before using them with `brew upgrade` and a reinstall of the skills. Additionally you should authenticate the CLI to your account with `bd auth` before beginning.

> **Tip:** you can run several steps at once — e.g. *"install the bitdrift Capture SDK in this app, then add screen tracking and network monitoring"* — and the skill sequences the work. The single-step prompts below are the reference for what's available.

---

## 1. Add the dependency

> **Prompt:** *"Install the bitdrift Capture SDK and build-tool plugin in this app."*

The skill adds the SDK dependency and the build plugin (which handles automatic network instrumentation and symbol/mapping uploads).

**Unlocks:** Everything. No other step works without this.

**Docs:** [SDK Quickstart](https://docs.bitdrift.io/sdk/quickstart)

---

## 2. Start the Logger

> **Prompt:** *"Initialize the bitdrift logger at app startup, as early as possible in the launch path."*

The skill starts the logger with your SDK key and a session strategy (Step 3), before any other SDK call.

**Unlocks:** Instant Insights dashboards (app launches, crashes, network, resources), the session Timeline, and all automatic instrumentation (memory pressure, battery, orientation changes, slow frames, thermal state) — collected immediately after start.

**Docs:** [Configuration](https://docs.bitdrift.io/sdk/features/configuration), [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

---

## 3. Confirm session strategy

> **Prompt:** *"Use a fixed session strategy for the bitdrift logger."* (or *"…switch to an activity-based session strategy with a 30-minute inactivity timeout."*)

A **fixed** strategy starts a fresh session on every launch — simplest to reason about, ideal for demos and verification. Choose **activity-based** if sessions should persist across process restarts and rotate only after inactivity.

**Unlocks:** Correct session grouping in Timeline.

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

---

## 4. Instrument screen views

> **Prompt:** *"Add bitdrift screen-view tracking for every screen, using a centralized navigation listener where the framework supports one."*

The skill logs a stable, snake_case screen name on each navigation (the label that becomes a Sankey node), preferring a centralized listener so both user and programmatic navigation are captured.

**Unlocks:** User Journey (Sankey) diagram in Instant Insights — the foundation for funnel analysis.

**Docs:** [Automatic Instrumentation → Screen Views](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

---

## 5. Identify users with Entity ID

> **Prompt:** *"Set the bitdrift entity ID at the user identity boundary (e.g. on login)."*

The skill sets the entity ID when the user is known. The value is hashed; plaintext is never stored.

**Unlocks:** The Entities feature — search any entity by name to see all their sessions, crashes, devices, and last location; queue a recording with **Record Next Online**; bookmark entities to share with your team.

**Docs:** [Entity ID (SDK)](https://docs.bitdrift.io/sdk/features/entity-id), [Entities (product)](https://docs.bitdrift.io/product/entities)

---

## 6. Capture network traffic

> **Prompt:** *"Enable bitdrift network capture on every HTTP client in this app, and add path templates for any routes with dynamic segments."*

The skill attaches the network integration to each HTTP client and collapses high-cardinality paths.

**Unlocks:** Network tab in Instant Insights (p50/p95 latency, error rate, throughput by endpoint), and network events on the Timeline alongside logs and screen views.

> ⚠️ **High-cardinality paths are required, not optional.** When a path embeds a dynamic segment (user ID, product ID, UUID), every request becomes a distinct value. The dashboard groups metrics by path and enforces **cardinality limits** (~1,000 group-by dimensions / ~30 min, 20,000 total) — exceed them and metrics are **silently dropped**. The prompt above tells the skill to add a stable path template to every dynamic route.

**Docs:** [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs), [Workflow cardinality limits](https://docs.bitdrift.io/product/workflows/actions)

---

## 7. Emit structured custom logs

> **Prompt:** *"Add structured bitdrift logs for the key events in this app (e.g. checkout started, payment failed) — use a stable event name as the message and put variable data in fields."*

The skill emits logs with stable event-name messages and field-based variable data (never interpolated into the message), at the right level (info for business events, warning for degraded state, error for failures), capturing stack traces for caught exceptions.

**Unlocks:** Workflow matching, custom metrics (count, rate, histogram of any field), Timeline breadcrumbs, alert triggers.

**Docs:** [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs)

---

## 8. Attach global fields

> **Prompt:** *"Attach bitdrift global fields for session-wide context (e.g. app variant, user tier), and set/remove them as that context changes."*

The skill adds fields that attach to every subsequent log, including a field provider for values that must survive a process restart.

> `user_id` is a special field: when set, it appears in the Timeline session header.

**Unlocks:** Dashboard filtering and slicing by any global field (e.g. isolate a release cohort by `app_variant`).

**Docs:** [Fields](https://docs.bitdrift.io/sdk/features/fields)

---

## 9. Report app launch TTI

> **Prompt:** *"Add bitdrift app-launch TTI reporting — capture process start early and report the time to first interactive frame."*

The skill captures the start timestamp in the launch path and reports the elapsed time once the first frame is drawn (once per logger start).

**Unlocks:** App Launch TTI chart in Instant Insights → UX (p50/p95/p99 across your population).

**Docs:** [Automatic Instrumentation → TTI](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

---

## 10. Measure operations with custom spans

> **Prompt:** *"Wrap the key multi-step operations in this app (e.g. checkout, product discovery) in bitdrift spans, nesting child spans under a parent where it makes sense."*

The skill adds spans (each emits a start and end log with `_duration_ms`), nesting children under parents to form a Timeline waterfall, and uses the track-span wrapper for synchronous work.

**Unlocks:** Spans waterfall in the Timeline; query `_duration_ms` in Workflows to plot p50/p95 of any operation across your user base.

**Docs:** [Spans (SDK)](https://docs.bitdrift.io/sdk/features/spans), [Spans Visualization](https://docs.bitdrift.io/product/timeline/spans-visualization)

---

## 11. Implement device identification for support

> **Prompt:** *"Add a bitdrift support affordance — surface a temporary device code / session URL in the app and a support-mode toggle that tags logs."*

The skill surfaces a short-lived device code or session URL and adds a toggle that attaches a `supportlog` field so support can filter to one device.

**Unlocks:** Support teams pull any user's session in real time without shipping debug builds. Works in production.

**Docs:** [Device](https://docs.bitdrift.io/sdk/features/device)

---

## 12. Upload symbol files for readable crash stacks

> **Prompt:** *"Wire up bitdrift symbol/mapping upload for release builds."* (driven via **bd-cli**)

The skill configures the build plugin to upload mappings/symbols after a release build, or sets up a manual `bd debug-files …` upload.

> The API key used for uploads is your **SDK key** (Admin → SDK Keys), not a separate API key.

**Unlocks:** Human-readable stack traces in the Issues view.

**Docs:** [Issues & Crashes → Uploading Debug Information Files](https://docs.bitdrift.io/sdk/features/fatal-issues)

---

## 13. New session on user logout or journey reset

> **Prompt:** *"Start a new bitdrift session on logout / journey reset, and re-apply the global fields afterward."*

The skill starts a new session at the right boundary and re-applies global fields (they're session-scoped and not carried across a new session).

**Unlocks:** Clean per-user Timeline entries.

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

---

## 14. Forward your existing log framework

> **Prompt:** *"Forward this app's existing logging framework (e.g. Timber / CocoaLumberjack / console) into bitdrift."*

The skill bridges your existing logger into bitdrift so those logs land in the Timeline with no change to existing call sites. If the app already has rich logging, run this early.

**Unlocks:** All existing debug logs become searchable in Timeline and usable as Workflow match conditions.

**Docs:** [Integrations](https://docs.bitdrift.io/sdk/integrations)

---

## Feature coverage summary

| Step | Prompt drives | bitdrift feature | Docs |
|------|---------------|-----------------|------|
| 1 | Install SDK + plugin | All features | [Quickstart](https://docs.bitdrift.io/sdk/quickstart) |
| 2 | Start the logger | Instant Insights, Timeline, automatic events | [Configuration](https://docs.bitdrift.io/sdk/features/configuration) |
| 3 | Session strategy | Correct session grouping | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 4 | Screen-view tracking | User Journey Sankey diagram | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 5 | Entity ID | Entities: per-user history, Record Next Online | [Entity ID](https://docs.bitdrift.io/sdk/features/entity-id) |
| 6 | Network capture + path templates | Network tab, request/response correlation | [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs) |
| 7 | Structured custom logs | Workflow matching, alerts, breadcrumbs | [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs) |
| 8 | Global fields | Dashboard filtering, session header user_id | [Fields](https://docs.bitdrift.io/sdk/features/fields) |
| 9 | App launch TTI | TTI histogram in Instant Insights → UX | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 10 | Custom spans | Spans waterfall, duration histograms | [Spans](https://docs.bitdrift.io/sdk/features/spans) |
| 11 | Device identification | Support tooling, production device lookup | [Device](https://docs.bitdrift.io/sdk/features/device) |
| 12 | Symbol/mapping upload | Readable crash stacks in Issues | [Issues & Crashes](https://docs.bitdrift.io/sdk/features/fatal-issues) |
| 13 | New session on reset | Clean per-user Timeline entries | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 14 | Log framework forwarding | Existing logs visible in Timeline | [Integrations](https://docs.bitdrift.io/sdk/integrations) |

---

## Turning signals into metrics and alerts (Workflows)

Some features need **Workflows** — server-side rules configured in the dashboard — to turn raw events into charts, alerts, and metrics. The SDK instrumentation above is the input; Workflows are the configuration. You can drive these from an agent too, via **bd-cli**.

> **Prompt:** *"Create a bitdrift workflow that alerts when the `payment_failed` event rate exceeds a threshold."* — or — *"…a custom metric for the p95 of the `checkout` span duration."*

**Automatic, no Workflow needed:** Instant Insights dashboards (crashes, network, memory, app launches); Session Timeline breadcrumbs; User Journey Sankey; TTI histogram; Spans waterfall; Entities view.

**Docs:** [Workflows](https://docs.bitdrift.io/product/workflows/overview), [Custom Metrics & Alerts](https://docs.bitdrift.io/product/workflows/actions)

---

## Tips for prompting the skill on a real app

- **Let the skill discover the app first.** A good opening prompt: *"Inspect this app and tell me where the bitdrift logger should start, which HTTP clients need instrumenting, and how navigation works — then propose an instrumentation plan."* The skill will find the launch entry point, every HTTP client, the navigation style, any existing logging framework, the SDK key location, and whether the SDK is already installed.
- **Run steps in dependency order.** Step 2 requires Step 1; Step 3 is part of the Step 2 call. After Steps 1–2 the rest are independent — ask only for what you need. Note Step 13 (new session) clears global fields, so the skill re-applies them; and Step 12 (symbols) only matters for release builds.
- **Ask the skill to verify.** End with *"compile the app and confirm the bitdrift instrumentation builds and data flows to the dashboard."* SDK calls are no-ops if the logger hasn't started, so a clean compile + launch is the first gate; then confirm sessions in Timeline, the Sankey from screen views, network events, TTI, and spans.
- **Keep it on stable APIs.** The skill avoids experimental, opt-in-required APIs by default. If a feature you want is only available experimentally, it will ask before opting in.
- **When in doubt, point it at the docs.** Ask the skill to confirm signatures via **bd-docs** for your installed SDK version rather than guessing.

---

## Platform notes

The prompts above are identical across platforms — the skill applies the right APIs. A few specifics it handles for you:

**iOS (Swift):** install via SPM (`bitdriftlabs/capture-ios`) or CocoaPods (`pod 'BitdriftCapture'`, `import Capture`); start in the SwiftUI `@main App` `init()` or UIKit `didFinishLaunchingWithOptions`; integrations (network, log forwarding) are **chained on the start call**, not wired per-client; entity ID is `setEntityID` (capital **ID**); symbols are **dSYMs**, not ProGuard; the SDK is added only to targets that start the logger (avoids duplicate-symbol warnings). Path templates apply on iOS too.

**React Native (TypeScript):** install `@bitdrift/react-native` then `pod install` (iOS); Android autolinks — so crash symbolication needs **both** JS source maps (Hermes) and native symbols. Start with `init(...)` in `App.tsx`/`index.js`; screen views hook into React Navigation `onStateChange` or Expo Router `usePathname()`. Network capture **isn't guaranteed automatic** — the skill wraps `fetch`/adds an interceptor where needed. JS error reporting currently requires the **New Architecture + Hermes** engine. Functions are top-level named exports (`init`, `info`, `addField`, …).

For authoritative, per-step platform detail, the bd-instrumentation skill ships `references/ios.md` and `references/react-native.md`, and confirms live signatures via **bd-docs**.
