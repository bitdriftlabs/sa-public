# Plan — make journey spans automatic in the instrumentation guide

**Target:** `instrumentation-guide/` in this repo
**Status:** ✅ **executed** — see [§10 What actually shipped](#10-what-actually-shipped). Kept on the branch
because §8.2's deferred test bar is still outstanding.
**Date:** planned 2026-08-23, executed 2026-08-24

> ## ⚠️ Execution constraint — documentation only
>
> When this plan is enacted, the work is **editing Markdown files and nothing else**. Do not build,
> install, launch, or drive any app. Do not deploy, create, update, or query workflows, dashboards,
> or sessions. Do not run `bd` commands against live account data. No emulators, no simulators, no
> `bd tail`.
>
> Everything in this plan is derivable from what is already in the repo — the two span commits
> (`be444d2`, `1cae16b`), the existing guide text, and the bitdrift-shop source. Read those; write
> the guides.
>
> The guides will be **tested separately and deliberately** once written, to control token spend.
> §8 below is therefore split: what must hold before the branch is published (desk-checkable) versus what is
> deferred to that separate test pass.

---

## 1. Goal

Today the guide treats screen views (Step 4) and spans (Step 10) as unrelated steps with very
different defaults:

| Step | Current default |
|------|-----------------|
| 4 — Screen views | **Every** screen, via a centralized nav listener |
| 10 — Spans | The **single most important** multi-step flow, "one parent span + obvious children" |

The result is a journey you can *see* (Sankey, funnel) but can't *time*. Conversion is measured
per step; latency is measured for one hand-picked flow, if at all.

**The change:** make screen-view instrumentation and span instrumentation a **matched pair, by
default**. Every element of a user journey that gets a screen name also gets a span. A POC run
then produces per-step duration percentiles for the same journey the funnel already charts,
with no extra prompt from the operator.

---

## 2. Why now — the evidence base

This is not speculative design; it was built and validated end-to-end in `sa-public/bitdrift-shop`
after the guide was last updated (guide update = `4d8038c`, span work = `be444d2`, `1cae16b`):

- **`be444d2`** — iOS: ~20 spans across screens, journey phases, recommendation engine,
  persistence, and image loading; 4 workflows (`bd-shop-21..24`) + 4 dashboards; cold start
  broken into a waterfall (`bd-shop-20`).
- **`1cae16b`** — Android: port to parity, same span names so one chart compares both platforms
  via the `platform` field; 4 workflows, 4 dashboards; verified with live emulator data.

Both commit messages carry a long list of traps that were hit for real. Those traps are the
single most valuable thing to move into the guide — an agent running the current Step 10 prompt
on a fresh app will hit most of them.

**Scope note.** `bitdrift poc scope V2.0.docx` has no span/journey-performance use case beyond
SC-1 ("Instrument 2–3 critical user flows … validate percentile accuracy"). **This plan does not
change the scope document.** It changes what the *default setup* produces, so SC-1 is satisfied
with far more depth than its test plan asks for, and a customer whose scope never mentioned spans
still ends the POC with per-step latency data. Deeper span-based journey-performance use cases
can be added to a future scope version once this is shipped and proven.

---

## 3. Design decisions

**D1 — No renumbering.** Steps 1–20 are cross-linked from the agent runbook, both cleanup guides,
the examples, and (externally) prior POC readouts. Expand **Steps 4, 9, 10** in place; do not
insert a new step. The one new prompt that has no home (span hygiene / helper) becomes a
sub-prompt inside Step 10.

**D2 — The pairing rule** (the core new contract, stated once and referenced everywhere):

> Every screen name emitted in Step 4 gets a `<screen>_screen_load` span in Step 10. Every named
> phase of the instrumented journey gets a `journey.<phase>` span. Steps 4 and 10 are verified
> against each other — a screen with no span, or a span naming a screen that is never logged, is
> a gate failure.

**D3 — Cold start becomes a waterfall** (Step 9), *in addition to* `logAppLaunchTTI`, not instead
of it. Root `app_cold_start` back-dated to real process start, with `sdk_init` / `scene_render` /
`state_restore` children. "Launch was slow" becomes "SDK init was slow" vs "first render was slow."

**D4 — Ship a helper, don't call `trackSpan` raw.** The SDK's `Logger.trackSpan` is unusable for
most journey work on Android (no `parentSpanId`, not suspend-capable, maps `CancellationException`
to FAILURE). The guide should instruct the skill to add a small per-platform bridge file, modeled
on `bitdrift-shop`'s `CaptureBridge.kt` / `CaptureBridge.swift`.

**D5 — React Native is an honest gap.** `@bitdrift/react-native` has **no span API**. `bitdrift-shop`
emulates one in `reactnative/src/utils/logger.ts` with paired start/end logs correlated by
`_span_id` and carrying `_duration_ms` / `_result` / `parent_span_id` — the same data shape the
dashboard queries. The guide must say this plainly and point at the shim, rather than implying
parity. Confirm current RN API state via **bd-docs** before writing this section.

**D6 — Two different durations, both wanted.** `bd-cuj`'s `measure_time_rule` measures wall-clock
between two screen events — it includes user think time. A span measures the app's own work. A
5-second checkout step could be a slow API or a user reading a form; only having both tells you
which. The guide must name this distinction, because a reader who has one will assume it covers
the other.

---

## 4. Per-file change list

### 4.1 `INSTRUMENTATION_GUIDE.md` (human / manual prompts)

| § | Change |
|---|--------|
| Intro paragraph | Add one line: steps 4 and 10 are a paired unit — screens define the journey, spans time it. |
| **Step 4** | Retitle → *"Instrument screen views (and pair them with load spans)"*. Add a forward-reference to Step 10's pairing rule and a note that the screen-name list produced here is the **input** to Step 10, so it should be captured (written down / grepped) not just implemented. |
| **Step 9** | Retitle → *"Report app launch TTI + cold-start span waterfall"*. New second prompt (draft in §5). Add the clock-domain trap (Android `SystemClock.uptimeMillis()` is monotonic; span start times want **epoch** — passing uptime through stamps the span in 1970). Add the `sdk_init` first-launch caveat: on a fresh install's first launch `sdk_init` ends before the on-device workflow config has arrived (~570ms vs ~14s for the other phases), so it appears in the Timeline waterfall but not in its chart. Not a bug; do not chase it during a demo. |
| **Step 10** | Rewrite the prompt from "wrap the key multi-step operations" to the pairing rule (draft in §5). Add three sub-sections: **10a** the pairing rule + naming convention, **10b** the span-hygiene checklist (§6), **10c** the helper bridge (D4) with the three concrete reasons `trackSpan` isn't enough. Update **Unlocks** to mention per-screen and per-phase percentile histograms, not just a waterfall. |
| **Step 19** | Add a paragraph: the same grep that validates funnel step names against emitted screen names should also validate them against emitted **span** names; add span-percentile charts to the Business/UX dashboard; state the D6 duration distinction; note the `y_axis.unit = MILLISECONDS` requirement at workflow *creation* (bd-shop-20 charted raw unitless numbers until it was bolted on later) and the `_result != canceled` filter for spans that legitimately cancel. |
| Feature coverage summary table | Row 4 → add "screen-load spans"; row 9 → add "cold-start waterfall"; row 10 → "Custom spans **for every journey element**". |
| POC coverage matrix | SC-1: expand notes — spans now cover every screen and journey phase by default, not 2–3 hand-picked flows. SC-7: note that per-step latency charts join the funnel on the Business/UX dashboard. No new SC IDs. |
| Tips section | Add a tip: ask the skill to emit the screen-name ↔ span-name parity table before writing any workflow. |
| Platform notes | Add per-platform span notes: iOS `parentSpanID` (capital ID) and `trackSpan` closure shape; Android bridge + cancellation mapping + clock domain; RN has no span API (D5). |

### 4.2 `AGENT_INSTRUMENTATION_GUIDE.md` (agent runbook)

| § | Change |
|---|--------|
| §1 Decision defaults | **The load-bearing edit.** Replace the Step 10 row: *"Wrap the single most important multi-step flow found"* → *"Span **every** screen instrumented in Step 4 (`<screen>_screen_load`) plus every phase of the journey chosen for Step 19 (`journey.<phase>`). Add the cold-start waterfall from Step 9. Do **not** ASK."* Add a Step 9 row for the cold-start waterfall (default: on). |
| §2 Execution order | Step 4 gate: add "screen-name inventory captured and recorded in the run report." Step 9 gate: add "root + 3 phase spans emit `_duration_ms`, root back-dated to process start." Step 10 gate: replace "start+end emit `_duration_ms`" with the parity assertion — *every* Step 4 screen has a span, *no* span names a screen that isn't emitted. Step 19 gate: add "span-percentile charts present on the Business/UX dashboard." |
| §2 warning blocks | Add a ⚠️ block for span hygiene alongside the existing Step 6 cardinality gate — same "hard requirement, not advisory" framing. Content = §6 checklist. |
| §3 Verification | New **V9 — Span/screen parity**: the parity table has no orphans on either side. New **V10 — Span data is real**: via bd-cli, each span name has non-zero events after exercising the flow; a span that only ever reports FAILURE or CANCELED is a hygiene bug, not a measurement. Amend **V7**: span-timing workflows are held to the CUJ bar (traffic is generatable → empty chart = FAIL), not the crash-workflow bar. |
| §4 Run report | Replace `spans_added: <flow + child spans>` with: `screen_spans:` (screen ↔ span parity table), `journey_spans:`, `cold_start_spans:`, `span_hygiene:` (checklist pass/fail per item). |

### 4.3 `CLEANUP_GUIDE.md` + `AGENT_CLEANUP_GUIDE.md`

The cleanup path currently assumes spans are a handful of call sites in one flow. After this
change it's ~20 call sites plus a new file.

- Order 11 (spans): prompt becomes *"Remove all bitdrift spans — screen-load, journey-phase,
  cold-start waterfall — and the `CaptureBridge` helper file added for them."*
- Order 12 (TTI): note that the cold-start waterfall comes out here too if it wasn't caught by
  order 11, and that removing the back-dated root span must not remove the process-start
  timestamp if `logAppLaunchTTI` is being kept.
- Checklist (`CLEANUP_GUIDE.md` "Verify the cleanup"): expand `- [ ] No span calls (10)` into
  screen-load / journey-phase / cold-start / helper-file items.
- `AGENT_CLEANUP_GUIDE.md` V1 greps: add `grep -r "startSpan\|trackSpan\|CaptureBridge"`.
- Also delete the span-timing workflows/dashboards under order 1 (they're `bd-cli` resources like
  any other Step 19 artifact) — same ASK-before-deleting rule applies.

### 4.4 `examples/` — new file

**`examples/journey-span-instrumentation.md`** — the worked example, sourced from `be444d2` /
`1cae16b`. Mirrors the existing `cuj-funnel-pitfalls.md` format (real failure → why it's silent →
how to catch it). Contents:

1. The parity table from bitdrift-shop (21 shared span names across iOS + Android).
2. Cold-start waterfall: what the four phases are and what each one told us.
3. The four workflows (`bd-shop-20..24`), why they're split by analytic question rather than one
   giant workflow, and why `bd-shop-21` has no combined chart (10 series is unreadable).
4. **The traps**, each with the real symptom:
   - Span inside `try { } catch { }` → catch swallows the error, span records SUCCESS on a failed
     load (caught by review on iOS).
   - `CancellationException` → FAILURE on Android: `LaunchedEffect(key)` cancels on ordinary
     scrolling, so partial durations flood the histogram.
   - A broad `catch (_: Exception)` inside a span body also swallows cancellation, defeating the
     CANCELED mapping.
   - Bare `return` inside a span closure exits the closure, not the caller — restructure as a
     returned signal.
   - Clock domain (uptime vs epoch) on Android.
   - Coverage gap: iOS spans existed only on the full-journey path while the app defaulted to the
     simplified journey → three charts were empty for a week. **Instrument every code path that
     the default configuration actually runs.**
   - Feature-flag-gated spans (`bd-shop-23` behind `recommendationsV2Enabled`) look broken until
     the flag is on — and need a headless toggle to be exercisable.
   - Several unrelated spans reporting an *identical* duration = one shared failure mode (this is
     how the backend-IP-drift bug was found), not several real measurements.
5. Duration semantics (D6), with the two chart types side by side.

### 4.5 `README.md`

- "What gets instrumented" paragraph: spans described as covering the journey, not a flow.
- Files table: new row for `examples/journey-span-instrumentation.md`.

### 4.6 Version bumps

Both guides go **1.1 → 1.2**; update the version banner line in each and the "covers the 20-step
guide" subtitle to mention the span pairing.

---

## 5. Draft prompt text

These are the user-visible deliverable — the "manual prompts" the guide is made of.

**Step 4 (revised):**

> *"Add bitdrift screen-view tracking for every screen, using a centralized navigation listener
> where the framework supports one. Then list every screen name the app now emits — this list is
> the input to Step 10."*

**Step 9 (new second prompt):**

> *"Break app cold start into a bitdrift span waterfall: a root `app_cold_start` span back-dated
> to the real process-start time, with child spans for SDK init, first render, and state restore.
> Keep the existing TTI report as well."*

**Step 10 (replacing the current prompt):**

> *"Add a bitdrift span for every element of the user journey: one `<screen>_screen_load` span per
> screen instrumented in Step 4, and one `journey.<phase>` span per phase of the critical flow,
> nested under a parent journey span via the parent-span ID. Add a small span-helper file if the
> SDK's own `trackSpan` can't express parenting, async work, or cancellation on this platform.
> Then show me a table of screen names against span names and flag anything unpaired."*

**Step 10 hygiene sub-prompt:**

> *"Review every span you added: is it outside the try/catch so a failure records FAILURE and not
> SUCCESS; is cancellation mapped to CANCELED rather than FAILURE; does no span body use a bare
> return; is the start time in the clock domain the SDK expects?"*

---

## 6. The span-hygiene checklist (new shared content block)

Authored once, referenced from `INSTRUMENTATION_GUIDE.md` Step 10b and the agent runbook's ⚠️
block. Each item is phrased as a checkable assertion because the agent guide needs it that way:

1. **Span wraps the try/catch, not the reverse.** A swallowing catch inside the span records
   SUCCESS on a failed operation.
2. **Cancellation maps to CANCELED, not FAILURE.** And no broad `catch (Exception)` inside a span
   body may swallow the cancellation before the wrapper sees it.
3. **No bare `return` inside a span closure** — it exits the closure only. Return a signal.
4. **Custom start times are in the SDK's clock domain** (epoch, not monotonic uptime).
5. **Children pass an explicit parent span ID.** No ambient/global span-context stack — concurrent
   loads will misattribute.
6. **Span names are stable and snake_case**, shared verbatim across platforms so one chart can
   compare them via the `platform` field.
7. **Every span name is reachable in the app's default configuration** — not only behind a
   non-default journey mode or an off-by-default feature flag. If it is gated, provide a headless
   toggle and say so.
8. **Charts set `y_axis.unit = MILLISECONDS` at creation**, and filter `_result != canceled` where
   cancellation is routine.

---

## 7. Work breakdown and order

| # | Task | Depends on |
|---|------|-----------|
| 1 | Confirm current span API surface per platform — especially the RN gap (D5) and iOS `parentSpanID`. **bd-docs search only**; where the docs are silent, read the call sites in `sa-public/bitdrift-shop` rather than running anything | — |
| 2 | Author `examples/journey-span-instrumentation.md` from `be444d2` / `1cae16b` | 1 |
| 3 | Author the shared span-hygiene block (§6) | 2 |
| 4 | Edit `INSTRUMENTATION_GUIDE.md` (§4.1) | 3 |
| 5 | Edit `AGENT_INSTRUMENTATION_GUIDE.md` (§4.2) — defaults, gates, V9/V10, run report | 4 |
| 6 | Edit both cleanup guides (§4.3) | 4 |
| 7 | `README.md` + version bumps (§4.5, §4.6) | 4–6 |
| 8 | Desk-check pass across all edited files: link integrity, step-number references, defaults/gates/run-report consistency between the human guide and the agent runbook, and instrumentation↔cleanup symmetry (§8.1) | 5–7 |

Steps 2–3 first is deliberate: the example file is where the hard-won detail lives, and both
guides then reference it rather than restating it.

**No task in this list runs an app, a build, or a `bd` command.** Task 8 replaces what would
normally be a dry run; the real run is deferred (§8.2).

---

## 8. Verification

### 8.1 Before the branch is published — desk-checkable, no execution

All of these are satisfied by reading the edited files:

- Every anchor link resolves; no step was renumbered; every `INSTRUMENTATION_GUIDE.md#N-...`
  reference in the agent runbook, both cleanup guides, and the examples still points at a real
  heading.
- **Symmetry:** every span category the instrumentation guide adds (screen-load, journey-phase,
  cold-start waterfall, helper bridge file) has a matching removal line in *both* cleanup guides
  and a matching item in the `CLEANUP_GUIDE.md` checklist.
- **Consistency:** the Step 10 default in the agent runbook §1, the Step 10 gate in §2, gates
  V9/V10 in §3, and the run-report fields in §4 all describe the same contract, in the same terms
  as the human guide's Step 10.
- The hygiene checklist (§6) appears once as authored content and is referenced — not restated —
  everywhere else.
- The span names and traps in `examples/journey-span-instrumentation.md` match what the
  bitdrift-shop source actually contains (verify by reading the files, not by running them).
- RN's missing span API is stated explicitly wherever spans are promised (D5) — the guide never
  implies parity it doesn't have.
- Version banners bumped to 1.2 in both guides.

### 8.2 Deferred to the separate test pass — do NOT attempt during this work

Recorded here so the later test has a written bar, not because anything below runs now:

- A fresh agent run of `AGENT_INSTRUMENTATION_GUIDE.md` on an uninstrumented app produces, with
  **no operator prompting**, a screen-load span per screen, journey-phase spans, and a cold-start
  waterfall.
- The run report contains a screen ↔ span parity table with no orphans (V9).
- Every span name has live data after exercising the flow (V10) — the bitdrift-shop
  simplified-journey gap is exactly the failure this gate exists to catch.
- The Business/UX dashboard shows funnel conversion *and* per-step latency percentiles side by
  side, with the wall-clock-vs-work-time distinction labeled (D6).
- Running the cleanup runbook afterwards leaves no `startSpan` / `trackSpan` / `CaptureBridge`
  references.

Because none of this is exercised before the branch is published, the guides land as **unvalidated
on a real app**. That's the accepted trade — the branch itself is where that gets resolved (§8.3).

### 8.3 Delivery — a working branch, not a PR

All of this work lands on a **branch of `sa-public`** (current branch is `main`; the guides live at
`sa-public/instrumentation-guide/`). No pull request, no merge to `main` as part of this work.

- Branch name: `journey-spans-guide` (or similar) off `main`.
- Commit the guide edits there and leave the branch open.
- The deferred test pass (§8.2) happens **on that branch**, and whatever it turns up is fixed with
  further commits to the same branch.
- The branch merges only after that testing — that decision is out of scope here.

Practical consequence for the enacting agent: commit to the branch, do not open a PR, do not merge,
and do not treat "guides written" as "guides done."

---

## 9. Risks and open questions

| Risk | Mitigation |
|------|------------|
| **~20 spans on an unfamiliar app is a lot of diff** for an agent to write unattended, and a bad span is worse than no span (it charts a wrong number confidently) | The hygiene checklist is a hard gate, not advice. Whether to cap the pairing at screens reachable in the Step 19 journey is a question the deferred test pass (§8.2) answers — write the full-sweep default now, and treat narrowing it as a follow-up edit if the test shows it's too noisy. |
| **The guides are unvalidated when first written** — no run proves the new defaults are executable | Accepted and deliberate (§8.2), to control token spend. Contained by the branch workflow (§8.3): nothing reaches `main` until the separate test pass runs on that branch. Mitigated further by writing every new default from a pattern that already exists in bitdrift-shop rather than inventing one. |
| **React Native has no span API** | D5 — document the paired-log shim explicitly and set expectations; do not let the runbook silently produce nothing on RN. |
| **Span volume vs. log budget** | Not measured in bitdrift-shop (a demo app with generated traffic). Worth a note in the guide that high-frequency spans — `screen_view_persist` fires on every transition, `product_image_load` per row — are the ones to reconsider on a real app. Open question: is there a documented per-session log-volume ceiling to cite? Check bd-docs. |
| **Guide length** | `INSTRUMENTATION_GUIDE.md` is already 448 lines. Push detail into the new example file; keep the step sections to prompt + unlocks + criteria + one pointer. |

**Open questions for the user:**

1. Should the full-app screen sweep be the default, or should it be scoped to the Step 19 journey
   (safer, less diff, but then a screen outside the journey has no timing)? Plan currently assumes
   **full sweep**, matching what bitdrift-shop actually does.
2. Should span-timing workflows/dashboards be added to Step 19's default dashboard set as a
   **fourth** dashboard (a "Latency" dashboard, as bitdrift-shop has with `bd-shop-20..24`), or
   folded into the existing Business/UX dashboard? Plan currently assumes **folded in**, to keep
   the "2–3 dashboards" promise in the SC-7 test plan intact.
3. Does a future POC scope V2.1 want an explicit span/journey-performance criterion, now that the
   default output would support one?


---

## 10. What actually shipped

Committed on `journey-spans-guide`. The plan was followed as written; two later review rounds were
not in it.

| Commit | What |
|---|---|
| `20704ed` | **v1.2** — the plan itself: Step 4/10 pairing, Step 9 cold-start waterfall, hygiene checklist, V9/V10, cleanup symmetry, `examples/journey-span-instrumentation.md` |
| `86b5147` | Review vs **bd-skills 0.1.13 / bd 0.2.20** |
| `71c650f` | **v1.3** — review vs **Capture SDK 0.23.12** |
| `a589b58` | Session-replay default clarified: enabled is the wanted state, disable only on an explicit prompt |

### Found by the two review rounds, not by the plan

- **`bd-issue-match` no longer exists.** Folded into `bd-cli`'s IssueMatch recipes. The runbook's P3
  preflight made it mandatory whenever Step 19 was in scope — which the no-scope default always
  includes — so an autonomous run HALTed at preflight every time. Blocking, and pre-existing.
- **Session replay is on by default** (`sessionReplayConfiguration` defaults to a live object on both
  platforms). The guides framed Step 17 as opt-in enablement, so an agent could skip it, believe
  replay was off, and ship it enabled.
- **Custom span times are both-or-neither** — a back-dated start with no custom end is silently
  tracked on system time. This was a defect in the plan's own Step 9 text.
- Smaller: `startResult`/`getSdkStatus`, `clearEntityId`, default W3C trace-propagation headers, the
  three-way Android WebView gate, `TimeSeriesMetadata.title`, memory-pressure version 0.23.1→0.23.2.

### Plan decisions that held

D1 (no renumbering) through D6 (two duration types) all survived contact. Open question 1 was
written as **full sweep** and open question 2 as **folded into Business/UX**, both as the plan
assumed — neither is settled until the test pass, and question 3 (a scope V2.1 criterion) is
untouched.

### Still outstanding

See [§11](#11-picking-this-up--next-session).

---

## 11. Picking this up — next session

Start here on a new machine. `git fetch origin && git checkout journey-spans-guide`.

**Standing constraint:** testing is to be done *carefully and deliberately*, to control token spend.
Nothing below should turn into an open-ended agent run.

### 11.1 The main outstanding work — validate the guides on a real app

The guides have never been executed. Four commits of documentation, zero runs. The bar is
[§8.2](#82-deferred-to-the-separate-test-pass--do-not-attempt-during-this-work); what §8.2 does not
say is **which app to test against**, because the original dry-run task was replaced by a desk
check. Decide that first. Three candidates, in rough order of value:

| Target | Why | Watch out |
|---|---|---|
| A genuinely uninstrumented app | The only honest test of "no operator prompting" | Needs a throwaway bitdrift account/app id so the test doesn't pollute real POC data |
| `bitdrift-shop/reactnative` | The one shop platform with no span work yet | **RN has no span API** (D5) — a correct run produces the paired-log shim, not native spans. Judge it against that, or the test reads as a failure when it isn't |
| `bitdrift-shop` iOS or Android | Fastest to run | Already fully instrumented, so it tests almost nothing about the new defaults |

Run the instrumentation runbook, then the cleanup runbook, and check every §8.2 assertion. Expect
the first run to surface prompt-level ambiguities rather than outright errors. Drive the app
**headlessly** rather than by hand — see [§11.6](#116-exercising-the-app-headlessly--and-a-follow-on).

### 11.2 Decisions the test pass should settle

- **Open question 1 — full sweep vs. journey-scoped spans.** Currently written as full sweep. If
  ~20 spans on an unfamiliar app proves too noisy or too large a diff, narrow Step 10's default to
  screens reachable in the Step 19 journey.
- **Open question 2 — a fourth "Latency" dashboard vs. folding span charts into Business/UX.**
  Currently folded in, to protect SC-7's "2–3 dashboards" promise.
- Whether the `bd-instrumentation` skill needs its own update: its span guidance is three bullets
  per platform that defer to bd-docs, with nothing about parent IDs, cancellation, or custom times.
  The v1.3 runbook now asks that skill for things it has no guidance on. That is the weakest link
  in the new defaults, and it is a **separate repo** (`bitdriftlabs/bd-skills`), not this branch.

### 11.3 Known gaps in the guides — three of four now closed

Found during the SDK 0.23.12 review and deliberately left alone at the time. Worked 2026-08-24;
outcomes below so none of this research is repeated.

- **Field and log-message scrubbing** (SDK 0.23.4) — **still open, deliberately deferred.** Not in
  the platform API surface, so it looks server-side; worth confirming via bd-docs. A PII-scrubbing
  step is arguably missing from a guide aimed at customer POCs, where privacy review is often the
  gating item.
- **`sleepMode`** — **closed, no change needed.** The premise ("deserves more") turned out to be
  wrong: there is no more to say that is both true and useful. The docs are near-silent (one ObjC
  snippet, one changelog rename), but the SDK source settles the two facts that matter, and the
  guide's existing Step 2 line was already correct on both:
  - Default is **disabled on both platforms** — Android `Configuration.kt`, `val sleepMode:
    SleepMode = SleepMode.DISABLED`; iOS swiftinterface, `sleepMode: SleepMode = .disabled` in both
    `Configuration.init` and the `start(...)` convenience. The docs' `sleepMode:NO` is an *ObjC*
    artifact — `CAPConfiguration`'s `@objc` inits require the parameter, while Swift and Kotlin
    default it. Not evidence of a default either way.
  - It is **runtime-toggleable**, not start-time only — `Capture.setSleepMode()` is public/static on
    both platforms, forwarding to the core's `setSleepModeEnabled(loggerId, enabled)`.
  - **What it actually suppresses remains unknown** and is not knowable from either platform's
    source: the Kotlin/Swift layers forward a boolean to the Rust core. The only prose anywhere is
    the enum's own doc comment, "Capture will operate in minimal activity mode." Ask bitdrift
    directly if a customer ever needs specifics; do not assert them.
- **Span volume vs. log budget** (§9) — **closed, written into Step 10** as a "Span volume"
  subsection, mirrored into the agent runbook's Step 10 row. Answer: **no documented per-app or
  per-session emission ceiling and no span-count budget**; the docs actively encourage free
  emission (the SDK uploads nothing by default). ~20 spans is neither supported nor contradicted —
  there is no span-count guidance at all. The four real numbers now cited in the guide: a span is
  **two logs** (confirmed on the Spans page — start/end share a span ID); **Record Session streams
  up to 100,000 logs** per capture, configurable per action; the ring buffer is **5 MiB disk /
  2 MiB RAM**, oldest-evicted; **cardinality limits (500 client dims/interval) bite on group-by
  fields, not span counts**. Backpressure **drops logs rather than blocking**. Note that bitdrift
  documents *no* warning about high-frequency spans — the guide's caution is arithmetic from their
  published numbers, and is worded so it does not read as their guidance. This also resolved a
  live conflict: Step 10 had been recommending per-row image loads and per-transition I/O with no
  caveat at all.
- **Open question 3** — **closed as far as this repo can close it.** Recorded in the guide's POC
  success-criteria section as a recommendation to whoever owns the scope template, with suggested
  wording ("Per-step latency percentiles across a complete user journey, charted alongside funnel
  conversion"). The decision itself is a product/scope-template call this repo does not own, and
  the test pass does not answer it.

### 11.4 Merge

Not merged, by design (§8.3). Merge to `main` once §8.2 passes. No PR was opened — that was the
agreed workflow, not an oversight.

### 11.5 What this was reviewed against

Re-check these before trusting the v1.3 claims; they move.

| | Version at review (2026-08-24) |
|---|---|
| Capture SDK | `v0.23.12-7-gb3cbde45` |
| bd CLI | 0.2.20 |
| bd skills | 0.1.13 (four skills: bd-cli, bd-cuj, bd-docs, bd-instrumentation) |

### 11.6 Exercising the app headlessly — and a follow-on

V10 ("every span name has live data") cannot be met by tapping through a simulator. The charts need
a journey run many times, and the failure this gate exists to catch — a span sitting on a code path
the default configuration never runs — only shows up across repeated, *unattended* runs. Hand-driving
also can't survive the crash and ANR demos, which kill the app by design.

**Tooling already exists** in `bitdrift-shop` on `main`. Don't rebuild it:

| | Where | What it does |
|---|---|---|
| iOS | `ios/scripts/demo-lib.sh` | Abstracts booted Simulator (`xcrun simctl`) and physical device (`xcrun devicectl`) behind one set of functions — `resolve_target sim\|device\|auto`, so callers never branch |
| iOS | `ios/scripts/watchdog.sh` | Relaunches after deliberate crashes, backgrounds the app for background-crash demos, suppresses macOS "app quit unexpectedly" dialogs (a *global* pref it restores on exit) |
| iOS | `ios/scripts/check-demo-state.sh` | Reads app state from a JSON file in the container, deliberately **not** UserDefaults — cfprefsd caches that domain in memory, so a host-side read returns values the app abandoned minutes ago |
| Android | `android/scripts/watchdog.sh` | adb-based: detects the system ANR dialog and force-quit deaths, performs a user-style recents swipe-dismiss, relaunches |
| Android | `android/scripts/check-demo-state.sh` | Same role as the iOS one |

Two mechanics worth knowing before using them:

- **Demo flags are set as launch arguments**, not by navigating to a settings screen — on iOS via
  NSArgumentDomain, e.g. `xcrun simctl launch <udid> ai.bitdrift.shop.ios -recommendations.active 1`.
  `DISARM_ARGS` in `demo-lib.sh` turns every flag off. A flag not wired through this mechanism
  cannot be exercised headlessly at all, which is exactly why the recommendation-engine spans sat
  unpopulated until that flag got a launch-argument path.
- **Android self-restarts after a deliberate crash** (it arms an AlarmManager first); iOS has no
  equivalent, which is the whole reason the iOS watchdog exists. Expect the two platforms to need
  different amounts of babysitting.

**Blocker for reusing them as-is:** every script is hardcoded to bitdrift-shop — `BUNDLE_ID`,
`PKG=ai.bitdrift.shop`, `ACTIVITY=ai.bitdrift.shop/.MainActivity`. Testing the runbook against a
genuinely uninstrumented app (§11.1) means overriding those, and `BUNDLE_ID` is the only one with an
env-var escape hatch today.

### Follow-on: extract this into its own instruction set

**Intent, not scheduled work.** These scripts are the most reusable thing in the repo and the least
discoverable — they live under one demo app's directory and read as that app's private tooling.
They should become a **repo-wide instruction set**, a sibling to `instrumentation-guide/` rather
than a subdirectory of `bitdrift-shop`.

Shape it the same way this guide is shaped, since that structure has now survived three revisions:
a human reference, an agent runbook with defaults and checkable gates, and worked examples carrying
the traps. The traps are already known and are the valuable part — the cfprefsd staleness, the
global macOS crash-dialog pref that must be restored on exit, launch-argument flag plumbing as a
hard requirement rather than a convenience, and the asymmetry between Android's self-restart and
iOS's need for a watchdog.

Scope to settle when it's picked up: parameterising bundle id / package / activity so it works on
any app; whether it covers physical devices or simulators/emulators only; and whether it stays
shell or becomes something an agent drives directly. Keep it independent of this branch — it is
not a prerequisite for merging, and it should not hold up §8.2.

---

## 12. Session log — 2026-08-24 (second session)

### 12.1 What got done

§11.3 closed except PII scrubbing — see the rewritten §11.3 above for outcomes and sources.
Committed and pushed as `5ff20bf`. No PR: raising one was considered and dropped mid-session.

### 12.2 Test target — decided, after ruling two out

**Chosen: a stripped copy of the iOS app**, at `bitdrift-shop/ios-clean`.

- **React Native — rejected.** A three-way parity sweep found the RN *app* already at parity (all
  19 screens, identical route names, full 7-step journey, logger start, session strategy, screen
  views, entity ID, custom logs, global fields, feature flags). The gaps are all demo-control
  machinery, and three of them are large: no persisted demo state (React `useState` only, so every
  chaos flag dies with the process), no launch-argument intake (no NSArgumentDomain equivalent), no
  state-publish file or watchdog scripts. Two findings make it wrong regardless of effort: RN has
  **no span API**, and this branch is entirely about spans — so a run there exercises the
  paired-log shim, not the Step 4/10 pairing. And `reactnative/ios/ShopDemoRN/BdCrash.m` has **zero
  references in `project.pbxproj`**, so native signals, true ANR and force-quit silently degrade to
  JS errors; the crash/ANR demos on RN-iOS are currently fiction. Bundle ids also diverge
  (`ShopDemoRN`), so no existing `bd-shop-*` workflow matches RN sessions.
- **Checking out a pre-span commit — rejected** by the user (no testing against old versions). For
  the record, it was viable: the span work is exactly `be444d2` (iOS) and `1cae16b` (Android), and
  iOS at `be444d2~1` was span-free while already having all 19 screens instrumented.

### 12.3 State of `bitdrift-shop/ios-clean` — READ THIS BEFORE RESUMING

- It is a **byte-identical copy** of `bitdrift-shop/ios/`, and `.local.xcconfig` came with it. So it
  carries the **same API key and the same bundle id, `ai.bitdrift.shop.ios`** — to the bitdrift
  platform this copy *is* the production demo app.
- Its sessions will land in the real `bd-shop` app beside live POC data, since the bundle id and key
  match. **The user has accepted this** — do not change the bundle id. Just remember when reading
  V10 that the app id is shared, so "this span has data" does not by itself mean *this* app sent it.
- It is **untracked and not gitignored** — it shows up in `git status` on this branch. Decide
  whether to ignore it or move it out of the repo.
- **Cleanup is now DONE** — see §12.7.

### 12.4 Cleanup preflight — done, all gates recorded

Ran against `AGENT_CLEANUP_GUIDE.md`. P2: 10 of 20 Swift files reference Capture. P3: pass.
P3b: platform `ios`. P4: WARN (untracked copy), accepted. A baseline build was run and **passed**,
though P5 has since been deleted from the runbook along with every other build gate (§12.6).

**Step 19 (order 1) was explicitly declined by the user and must stay out of scope.** The copy's 19
local workflow JSONs and 6 dashboard JSONs mirror the *real* `bd-shop-*` account resources that the
live iOS and Android apps depend on. Deleting them would destroy production POC assets. Record it
in the run report as intentionally kept.

### 12.5 Resuming the cleanup

Build/verify command:

```
cd bitdrift-shop/ios-clean && xcodebuild -project BitdriftShop.xcodeproj -scheme BitdriftShop \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/iosclean-dd build
```

Carry these scoping decisions forward — the runbook does not address them:

- **Preserve** `scripts/demo-lib.sh`, `scripts/watchdog.sh`, `scripts/check-demo-state.sh`. They are
  headless app-driving tooling needed for the later test (§11.6), not bitdrift instrumentation.
  Remove bitdrift-specific scripts (`upload-symbols.sh`, `deploy-workflows.sh`).
- **Leave credential values** in `local.xcconfig` / `.local.xcconfig` — needed to re-instrument.
- There is an **"Upload bitdrift Symbols" run script build phase** in the target (order 9 / Step 12).
- The SPM dependency is **`capture-ios`** (order 20 / Step 1).

A 720K source snapshot was taken at `/tmp/ios-clean-snapshot`. **`/tmp` is ephemeral — assume it is
gone.** `bitdrift-shop/ios/` is the real source of truth; re-copy from there if needed.

### 12.6 First §8.2 finding — build gates removed from cleanup entirely

Surfaced while *preparing* the run, before executing a step: `AGENT_CLEANUP_GUIDE.md` §2 demanded a
build gate after **each** of orders 3–20 — 18 `xcodebuild` runs, 40+ minutes on iOS, impractical
enough that any real run would deviate.

The deeper problem was that it applied an instrumentation-shaped rule to a removal. Adding code
needs a gate per step because each step introduces new failure surface. Removal is monotonic toward
a known end state, so an intermediate break is transient and a final build tells you nothing the
§3 greps don't.

**Resolved: every build gate is gone from both cleanup guides.** The per-order gates, preflight P5,
and V2 ("Build is clean from scratch") were all removed; V3–V5 renumbered to V2–V4. Both guides now
state that verifying compilation is the **caller's** responsibility, and §2's reverse-order
rationale no longer claims per-step compilation, since nothing verified it.

Consequence to be aware of: a cleanup run can now report green having left the project
non-compiling. That is deliberate — the run asserts references are gone, not that the app builds.
The one case that argued for keeping gates is **partial** removal, where the end state still holds
live bitdrift code; that was considered and rejected in favour of removing them uniformly.


---

## 12.7 Cleanup executed — `ios-clean` is a clean baseline

Ran `AGENT_CLEANUP_GUIDE.md` against `bitdrift-shop/ios-clean`, 2026-08-24. Step 19 out of scope
throughout; **no `bd` command was run and no server-side resource was queried or touched.**

```
platform:           ios
categories_removed: spans (screen-load, journey-phase, cold-start waterfall, helper
                    bridge), app-launch TTI, global fields + FieldProvider, entity ID,
                    feature-flag exposures, session rotation, device-code affordance,
                    custom-log emission, screen-view emission, network path templates,
                    logger start + Configuration, dSYM upload build phase, SPM
                    dependency, local workflow/dashboard artifacts, instrumentation
                    docs and comments
categories_skipped: Step 19 server-side — declined; shares an app id with the live app
gates:              V1 pass  V2 pass  V3 pass  V4 pass   (no build gate — removed §12.6;
                    built anyway, clean build SUCCEEDED, zero Capture refs in build log)
residual_refs:      none
server_side_state:  intentionally kept per user decision
```

Scale: 14 files touched, `CaptureBridge.swift` (362 lines) deleted, 11 `trackSpan` closures
unwrapped, 4 `startSpan`/`end` pairs removed, 29 single-line field/flag/session calls removed,
126 orphaned comment lines stripped, README 598 → ~340 lines.

**Deliberately left:** `ScreenLogger` as an os.log-only facade (it had **75** call sites, and an app
with pre-existing logging is a *better* baseline — Step 14 is literally "forward your existing log
framework"); credentials in `local.xcconfig`; `demo-lib.sh` / `watchdog.sh` / `check-demo-state.sh`;
and all branding (`BitdriftShopApp`, `BitdriftLogo`, bundle id) — identity, not instrumentation.

**Not run.** The app builds clean but has never been launched. Three unwrapped sites became
`await { … }()` closures to preserve their internal `return`s — semantically equivalent, but only a
launch proves it.

### 12.8 Six findings, all fixed in the guides

| # | Finding | Fix |
|---|---|---|
| 1 | **Docs and comments are an answer key.** No grep catches prose. The README documented every span name and the helper file; 126 in-code `// bitdrift SDK:` comments outlived every call site. For a cleanup that's cosmetic — but when the app is being cleaned *so the instrumentation guide can be re-run against it*, leaving them invalidates the test outright: the next agent reads the answer instead of finding it | New **order 2b** + ⚠️ note in both cleanup guides; V1 and the human checklist extended to prose; new **P9** preflight in `AGENT_INSTRUMENTATION_GUIDE.md` that WARNs on residue and requires the run report to name what was pre-supplied |
| 2 | **No distinction between the app's own logging and bitdrift's.** Order 14 read literally ("remove all structured custom logs") deletes an app-owned facade and every call site with it | Orders 14 and 17 now say to strip the bitdrift *emission* inside a facade and keep the facade, its call sites, and any app-owned behaviour the nav listener drives |
| 3 | **Path templates are a signature change, not a header line.** `pathTemplate:` was threaded through the request builder and 6 call sites | Order 15 now describes the ripple explicitly |
| 4 | **No guidance on app tooling vs. bitdrift tooling in `scripts/`.** Delete wrongly and the headless tooling the later test depends on goes with it | Order 9 now says to judge by purpose, not by whether `bd` appears in the file |
| 5 | **"Order is fixed" was wrong** once build gates were removed. File-by-file was markedly faster — one file often carries five orders' worth of call sites | §2 reframed: recommended default on a full revert, still binding on a *partial* removal |
| 6 | **V1 could not see the Xcode build phase.** The dSYM upload is a `PBXShellScriptBuildPhase` in `project.pbxproj`, invisible to a source grep | V1 and the human checklist now check build phases and Swift-package references |

### 12.9 Still outstanding

- **Run the instrumentation runbook against `ios-clean`** — the actual §8.2 bar. Everything above was
  preparation. Note P9 will now WARN on nothing, since the docs and comments are gone; that was the
  point.
- The app has not been launched (above).
- PII scrubbing (§11.3) remains deferred.
- Sessions from `ios-clean` will land in the real `bd-shop` app — accepted, see §12.3.
