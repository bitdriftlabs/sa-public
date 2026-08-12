# What journey led to the crash?

Crash reports tell you *what* broke, not *how the user got there*. This attaches
the path to the report itself.

Reference implementation: [`bitdrift-shop/ios`](../../bitdrift-shop/ios) —
`ScreenLogger.swift` (the register), `CaptureBridge.swift` (the next-launch
path), `workflows/bd-shop-18-*` (the Ripsaw script).

## Why not just build a Sankey ending in a crash?

Because on iOS it cannot close. This was measured on device
(`capture-ios` 0.23.11), not inferred:

| Flow shape | Result |
|---|---|
| `APP_IOS_BUILT_IN_CRASH` alone | 37 matches |
| screen view → crash (2 steps) | **0** |
| crash → screen view (2 steps) | **0** |
| screen view → loop → crash (3 steps) | **0** |
| screen view → loop → a normal screen (3 steps) | 122 matches, 22 links |

Multi-step flows and looping Sankeys work fine. Per-journey `startNewSession()`
is fine too — a 3-step Sankey was verified populating with rotation on. The one
thing that does not work is `APP_IOS_BUILT_IN_CRASH` / `APP_IOS_BUILT_IN_ANR`
advancing a multi-step flow, in either direction. They match only as a
standalone first step.

> An earlier version of this document blamed session attribution and
> `startNewSession()`. Both were tested and neither is the cause. The blocker is
> narrower and more specific: the fatal-issue events themselves.

A Sankey with an unreachable terminal renders **empty rather than erroring**, so
this fails silently. If you need a Sankey during a crash run, terminate it on the
*screen where crashes happen* instead of on the crash.

## The approach: put the path on the report

Global fields ride onto the crash report. So keep a small shift register of
recent screens as global fields, and every crash arrives already carrying the
path — no flow, no session correlation, nothing to close.

### Step 1 — the shift register

Wherever you already call `logScreenView`:

```swift
private static let trailDepth = 5          // hard ceiling, see below
private static var recent: [String] = []

func onScreen(_ name: String) {
    Logger.logScreenView(screenName: name)

    // Collapse consecutive repeats — navigation often logs the same screen
    // twice (initial + explicit), which would burn slots and push real
    // history off the end.
    if recent.first != name {
        recent.insert(name, at: 0)
        if recent.count > trailDepth { recent.removeLast() }
    }

    Logger.addField(withKey: "screen_current", value: name)
    for i in 1 ..< trailDepth {
        // "none" rather than omitting: a stable field set distinguishes
        // "early in the session" from "the register failed".
        Logger.addField(withKey: "screen_prev_\(i)",
                        value: i < recent.count ? recent[i] : "none")
    }

    // Survives the process dying — see Step 2.
    prefs.set(recent.joined(separator: ">"), forKey: "screen_trail")
    prefs.set(name, forKey: "last_screen")
    prefs.synchronize()
}
```

**Five is a ceiling, not a default to tune up.** Every entry is a global field,
and global fields attach to *every* log the app emits — not just the crash
report. Five means five extra key-values on every log line, which is already a
real cost at production volume. Reading this as "capture the whole journey" and
setting it to 100 multiplies your entire telemetry stream to answer a question
that only needs the tail of it.

### Step 2 — the next-launch path, for hangs and OOM

Hangs (`0x8BADF00D`) and jetsam kills produce no report at the moment they
happen; the process is simply gone. Nothing in Step 1 can help, because in-memory
global fields die with the process. Report them after the restart instead:

```swift
let trail = prefs.string(forKey: "screen_trail") ?? "unknown"
let last  = prefs.string(forKey: "last_screen")  ?? "unknown"
prefs.removeObject(forKey: "screen_trail")       // clear, or a later launch
prefs.removeObject(forKey: "last_screen")        // inherits a stale path
prefs.synchronize()

if let info = Logger.previousRunInfo {
    Logger.logError("previous_run_terminated", fields: [
        "termination_reason": info.terminationReason.rawValue,
        "crashed_on_screen": last,
        "crashed_on_trail": trail,
    ])
}
```

Read it **before** the first screen view of the new launch, or it has already
been overwritten. Clear it after reading, or a launch that dies before reaching
any screen inherits the previous run's path.

Note this is a plain log, not a global field, so it has no per-log budget — the
persisted trail here can be much deeper than five if you want it.

### Step 3 — chart it (Ripsaw)

A server-side `issue_match` step reads the register straight off the report:

```ripsaw
cur = .fields.screen_current
last_screen = if is_string(cur) { to_string(cur) } else { "unknown" }
p1 = .fields.screen_prev_1
came_from = if is_string(p1) { to_string(p1) } else { "unknown" }
p2 = .fields.screen_prev_2
prev2 = if is_string(p2) { to_string(p2) } else { "none" }
crash_path = prev2 + ">" + came_from + ">" + last_screen
[
  add_field("last_screen", last_screen),
  add_field("came_from", came_from),
  add_field("crash_path", crash_path)
]
```

Live output from the reference app:

| `crash_path` | count |
|---|---|
| `Welcome>Browse>ProductDetail` | 22 |
| `ProductDetail>Cart>CheckoutGuest` | 4 |
| `Browse>ProductDetail>Cart` | 2 |

**Three deep, not five, on purpose.** As a chart dimension each distinct path is
a tag combination, and the budget is 500 per metric per interval. Overflow does
not error — it silently folds into an `other` bucket, which reads as "most
crashes come from `other`" rather than "this dimension overflowed."

Deploy it:

```bash
bd workflow create crash-journey-ripsaw.workflow.json \
  --metadata-file       crash-journey-ripsaw.metadata.json \
  --chart-metadata-file crash-journey-ripsaw.chart-metadata.json
bd workflow deploy <id>
```

Creating compiles the Ripsaw program, so `create` doubles as the syntax check —
a bad script is rejected with the full compiler diagnostic.

### Step 4 — analyse it (agent)

For the full five-deep paths, joins against feature flags and app version, and an
honest count of the reports that carry no path at all, use an agent reading
reports directly — no metric emission, so no cardinality ceiling. Prompt:
[`crash-journey-agent-prompt.md`](crash-journey-agent-prompt.md).

## What you will see, and what it means

- **Not every crash carries the path.** Kinds the OS reports on the next launch
  (often `EXC_CRASH`) arrive in a fresh process where no global fields are set,
  and attribute as `unknown`. In the reference app `EXC_CRASH` was ~67% unknown
  while `EXC_BREAKPOINT` was ~15%. This is a property of iOS crash capture, not a
  broken register — chart screen attribution split by error kind and it is
  obvious which is which.
- **`none` in the later slots** means the crash fired before the register filled,
  i.e. a short journey. Working as intended.
- **Consecutive duplicates** will quietly eat your depth if you skip the collapse
  in Step 1.

## Notes

- Workflows only evaluate sessions that start **after** deployment. Relaunch
  before judging whether something works.
- Editing a deployed workflow needs `stop` → `update` → `deploy`; its config is
  locked while live. Metadata-only edits (titles, display mode) apply without a
  stop and without resetting the evaluation window — prefer those.
- Multi-entry chart-metadata files must be sent alongside `--workflow-file`; the
  API rejects them alone.
- Step 1 alone covers ordinary crashes. Step 2 is what buys you hangs and OOM
  kills, which for many iOS apps are the largest crash class by volume.

## Files

| File | What it is |
|---|---|
| [`crash-journey-ripsaw.workflow.json`](crash-journey-ripsaw.workflow.json) | Step 3 — Ripsaw `issue_match`, charts the paths (+ `.metadata` / `.chart-metadata`) |
| [`crash-journey-agent-prompt.md`](crash-journey-agent-prompt.md) | Step 4 — agent prompt for full-depth analysis |
| [`last-screen-before-crash.workflow.json`](last-screen-before-crash.workflow.json) | Step 2 — charts `previous_run_terminated`, the hang/OOM path (+ metadata) |

The Step 2 workflow is still the only way to see hangs and jetsam kills, which
never produce an in-process report for Step 3 to read. Deploy both.
