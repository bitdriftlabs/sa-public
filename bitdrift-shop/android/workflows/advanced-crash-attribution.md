# Advanced Crash Attribution: Blocking Thread & Vendor SDK

Three workflows — `bd-shop-08-blocking-thread.json`, `bd-shop-09-vendor-sdk-attribution.json`,
and `bd-shop-10-attribution-rate.json` — that turn two crash types (`lock_contention`,
`vendor_sdk_interceptor`/`vendor_sdk_analytics`) into standing, ingest-time attribution
charts instead of one-off reads of individual crash reports.

## Why

Bugsnag, Embrace, and similar tools already show you a full thread dump per crash, and
Sentry/Datadog already classify in-app vs. third-party stack frames per crash. None of that
is unique to bitdrift — the raw data these workflows read (`thread_details`, cross-error
stack frames) is the kind of thing any capable crash reporter surfaces on a single report.

What's different is turning that per-report data into a **persistent, ongoing
`metric_chart_rule`** — grouped by blocking thread or vendor SDK, computed automatically at
ingest, across every crash — rather than a human reading one report at a time or running a
saved search after the fact. That's the honest differentiator: not "we can see the data,"
but "this is aggregated for you continuously without a custom pipeline."

## The two crash types these charts read

- **`lock_contention`** (`Crashes.kt`): three real, uncorrelated thread states in one
  report — `image-decode-thread` holds a monitor and is genuinely `TIMED_WAITING`, the main
  thread is genuinely `BLOCKED` on the same monitor, and a third, uninvolved
  `anr-watchdog-thread` converts the block into a crash after a fixed delay. It's a
  synthetic stand-in for a real ANR (deliberately turned into a crash so it lands in the
  existing capture pipeline), not a real ANR — see `Crashes.kt`'s own comments for why.
- **`vendor_sdk_interceptor` / `vendor_sdk_analytics`**: two fake OkHttp interceptors
  (`com.adsdk.fake.AdRequestInterceptor`, `com.analytics.fake.AnalyticsPingInterceptor`)
  that throw before any network I/O starts, so the resulting crash carries real
  `com.adsdk.fake.*` / `com.analytics.fake.*` stack frames with no dependency on network
  reachability.

## `bd-shop-08-blocking-thread.json` — "Which thread is blocking this crash"

Matches `lock_contention` crashes by name-checking `.thread_details.threads[].name`
against an **illustrative allowlist**, not a general detector:

```bdrl
if .type != "JVMCrash" {
  abort
}

# Thread names specific to real lock/monitor contention. Do not add
# oom-allocator/worker-thread here -- those already belong to unrelated,
# non-contention crash types (crashOomAllocatorThread/crashRuntimeBackgroundThread).
known_threads = ["image-decode-thread"]

matches = filter(array!(.thread_details.threads)) -> |_i, thread| {
  is_string(thread.name) && any(known_threads) -> |_j, kt| { kt == thread.name }
}

if length(matches) == 0 {
  abort
}

holder = matches[0]
if true {
  add_field("blocking_thread", string(holder.name) ?? "unknown")
}
if true {
  add_field("blocking_thread_state", string(holder.state) ?? "unknown")
}

reporting = filter(array!(.thread_details.threads)) -> |_i, thread| {
  thread.active == true
}
if length(reporting) > 0 {
  add_field("reporting_thread", string(reporting[0].name) ?? "unknown")
}

# Cheap cross-reference: was this contention captured under memory pressure?
total = to_int(.app_metrics.memory.total)
free = to_int(.app_metrics.memory.free)
if total > 0 {
  pct, err = (free * 100) / total
  if err == null {
    free_pct = to_int(pct)
    pressure = if free_pct < 15 { "low" } else { "normal" }
    add_field("memory_pressure", pressure)
  }
}
```

Notes on a few non-obvious BDRL constraints that shaped this script (learned by iterating
against the live compiler, since some diverge from the docs): `filter()`'s type-checker can't
statically prove a two-level nested path like `.thread_details.threads` is an array unless
it's wrapped in `array!(...)` first; membership-testing against a list requires `any(list) ->
|_i, x| { x == value }` rather than `contains(list, value)` (`contains` is string-substring
only); the integer-division operator `//` documented in the language reference isn't accepted
by the live compiler — use `/` (float division) plus `to_int()` and handle its error instead;
`if`/`else` can't be inlined directly as a function argument — assign it to a variable first;
and every statement in a block except the last must have its value actually used, so
non-final `add_field()` calls each need wrapping in their own `if true { ... }` block.

`known_threads` names threads you already know about — it doesn't discover an unregistered
rogue thread on its own. That's fine for this demo (there's exactly one contention-related
thread name to watch for), but it's not a general "find whatever's blocking" mechanism.

One action, `blocking-thread-count`: `metric_chart_rule` count grouped by `blocking_thread`
— a multi-series time series (same shape as `bd-shop-03-crash-analytics.json`'s
`crash-count-by-type`), not a ranked list. `blocking_thread_state`, `reporting_thread`, and
`memory_pressure` are additional fields on the same synthetic log, available as secondary
breakdowns via "Customize Dimensions" on the chart.

This is the deeper, engineer-focused half of the story — lead with it for a technical
audience, or as the escalation after vendor SDK for a mixed one.

## `bd-shop-09-vendor-sdk-attribution.json` — "Which vendor SDK is causing this crash"

Searches every error's stack frames for either fake-vendor namespace:

```bdrl
if .type != "JVMCrash" {
  abort
}

adsdk_matches = flatten(map(.errors) -> |_i, error| {
  filter(error.stack_trace) -> |_j, frame| {
    is_string(frame.class_name) && starts_with(frame.class_name, "com.adsdk.")
  }
})

analytics_matches = flatten(map(.errors) -> |_i, error| {
  filter(error.stack_trace) -> |_j, frame| {
    is_string(frame.class_name) && starts_with(frame.class_name, "com.analytics.fake.")
  }
})

vendor_sdk = "app_code"
if length(adsdk_matches) > 0 {
  vendor_sdk = "adsdk"
} else if length(analytics_matches) > 0 {
  vendor_sdk = "analytics_sdk"
}

if true {
  add_field("vendor_sdk", vendor_sdk)
}

# Safe here ONLY because both interceptors throw a fixed literal string each
# (bounded to 2 total values) -- do not copy this pattern for a real vendor's
# .reason, which is unbounded free text and would violate cardinality limits.
if vendor_sdk != "app_code" && length(.errors) > 0 {
  add_field("vendor_reason", string(.errors[0].reason) ?? "unknown")
}
```

This is a direct application of the "search all stack frames across all errors" recipe
documented in bitdrift's live docs (`docs.bitdrift.io/product/workflows/scripting/functions.md`,
the `add_field` worked example) and mirrored in the local `bd-cli` skill's
`recipes/issue-match.md` (`.errors[0].stack_trace[1].symbolicated_name`). The script never
aborts, so every JVM crash gets bucketed into `app_code`, `adsdk`, or `analytics_sdk` —
that's intentional, since the chart's whole point is comparing all three, not isolating one.

One action, `vendor-sdk-count`: `metric_chart_rule` count grouped by `vendor_sdk`.
`vendor_reason` is a secondary breakdown via "Customize Dimensions."

**Business framing:** "X% of crashes are attributable to [vendor]" lands with a
non-engineer audience in a way the thread-contention scenario doesn't — lead with this one
for a mixed audience.

**Scope note — this pattern isn't Android-specific.** The identical technique (searching
stack frames by namespace) works over `.binary_images[]` for native crashes on any platform
too; this checkout just doesn't have a native (`.so`) third-party library to demo it
against — confirmed no NDK/CMake exists in this project. Naming that gap here avoids it
reading as an unaddressed question from a technical audience who knows bitdrift also
handles native crash symbolication.

## `bd-shop-10-attribution-rate.json` — "% of crashes with a known cause"

Ties the two scenarios above into one closing chart: what fraction of *all* crashes did
bitdrift successfully attribute to a specific cause. Two independent flows feed a `rate`
action — a numerator/denominator pair BDRL supports natively but no other `bd-shop-0N`
workflow uses yet:

```bdrl
# Denominator flow: every crash, unconditionally.
true
```

A comment-only program with no actual statement compiles and matches everything just fine,
but the workflow graph has nothing to summarize for that step and renders it as an empty
match group. A trivial real statement (`true`) fixes that without changing behavior.

```bdrl
# Numerator flow: only crashes attributable to a known thread or vendor SDK.
known_threads = ["image-decode-thread"]
thread_match = length(filter(array!(.thread_details.threads)) -> |_i, thread| {
  is_string(thread.name) && any(known_threads) -> |_j, kt| { kt == thread.name }
}) > 0

vendor_match = length(flatten(map(.errors) -> |_i, error| {
  filter(error.stack_trace) -> |_j, frame| {
    is_string(frame.class_name) &&
      (starts_with(frame.class_name, "com.adsdk.") || starts_with(frame.class_name, "com.analytics.fake."))
  }
})) > 0

if !thread_match && !vendor_match {
  abort
}
```

Same detection logic as 08/09, reused rather than duplicated conceptually. One action,
`attribution-rate`, a `rate` chart over the two flows above.

## Presentation

Treat these as two distinct beats, plus `bd-shop-10` as the closer — not one continuous
flow. Each scenario has its own memorable hook; blending them reads as a generic "BDRL is
powerful" takeaway instead. For a mixed audience, lead with vendor SDK (it has the business
angle), then escalate to thread-blocking as the deeper, engineer-focused half, and close
with the attribution-rate chart tying both together.

## Deploy

```bash
bd workflow create workflows/bd-shop-08-blocking-thread.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-08-blocking-thread.chart.json
bd workflow create workflows/bd-shop-09-vendor-sdk-attribution.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-09-vendor-sdk-attribution.chart.json
bd workflow create workflows/bd-shop-10-attribution-rate.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-10-attribution-rate.chart.json
```
