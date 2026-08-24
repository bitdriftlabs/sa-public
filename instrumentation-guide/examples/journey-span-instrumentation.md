# Spanning a user journey: what it looks like, and eight ways it goes quietly wrong

Worked example for [Step 4](../INSTRUMENTATION_GUIDE.md#4-instrument-screen-views-and-pair-them-with-load-spans),
[Step 9](../INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti--cold-start-span-waterfall) and
[Step 10](../INSTRUMENTATION_GUIDE.md#10-span-every-element-of-the-user-journey), drawn from
instrumenting the bitdrift-shop demo app on iOS and then porting it to Android for parity.

Everything below was hit for real. As with
[cuj-funnel-pitfalls.md](cuj-funnel-pitfalls.md), the theme is that none of these produce an
error — the app builds, the spans emit, the charts deploy, and the numbers are wrong or absent.

---

## 1. What "spanning the journey" produces

Screen views tell you *where* users went. Spans tell you *how long each of those places took*.
Instrumented as a pair, one journey yields three layers:

| Layer | Spans | Question it answers |
|-------|-------|---------------------|
| Cold start | `app_cold_start` + `sdk_init` / `scene_render` / `state_restore` | Is launch slow because of the SDK, the first render, or our own startup work? |
| Screen load | `welcome_screen_load`, `browse_screen_load`, `product_detail_load`, `cart_screen_load`, `checkout_screen_load`, `payment_screen_load`, `confirmation_screen_load`, `product_image_load` | Which step of the funnel is slow to become usable? |
| Journey phase | `discovery_fetch`, `product_view`, `wishlist_add`, `cart_assembly`, `checkout.payment`, `checkout.confirmation` | Within a step, which sub-operation costs the time? |

Plus whatever the app's own hot paths are — in the demo, `score_products.parse_catalog` vs
`score_products.similarity_pass` (is a slow recommendation call parsing, or the O(n·m) pass?),
and `screen_view_persist` / `demo_state_publish` for I/O that runs on every transition.

**Use identical span names on every platform.** The demo shares 21 span names across iOS and
Android, so a single chart compares the two by filtering on a `platform` global field. Different
names per platform means two charts that can never be put side by side.

### Grouping them into workflows

One workflow per coherent analytic question, not one workflow for all spans:

| Workflow | Covers |
|----------|--------|
| Cold-start timings | The 4 waterfall phases: individual histograms + one comparison chart |
| Screen-load timings | Every `*_screen_load` span, individual histograms only |
| Journey sub-phase timings | The 6 phase spans: individual histograms + one comparison chart |
| App-specific hot paths | e.g. recommendation engine, persistence I/O |

The screen-load workflow has **no** combined comparison chart on purpose: 9 series on one line
chart is past the point of being readable. Comparison charts are for small, related sets.

---

## 2. The eight traps

### 2.1 The span is inside the try/catch, so failures report SUCCESS

The most damaging one, because the chart looks healthy.

```kotlin
// WRONG — the catch swallows the error, the span closes SUCCESS on a failed load
try {
    trackSpan("browse_screen_load") { loadCatalog() }
} catch (e: Exception) { /* best-effort */ }
```

Written the other way round it's worse still: with the `try` *inside* the span body, the span
never sees the throw at all. Either way the failed load lands in the latency histogram as a
successful one, and typically a *fast* one, because failing early is quick — so the p50 improves
when the app breaks.

**The span must wrap the try/catch, and the catch must not swallow what the span needs to see.**

### 2.2 Cancellation recorded as FAILURE (and cancellation is not rare)

On Android, `Logger.trackSpan` maps every throwable to FAILURE — including
`CancellationException`. That is not an edge case: `LaunchedEffect(key)` cancels its coroutine
whenever the key changes or the composable leaves composition, so ordinary scrolling produces a
stream of "failed" spans whose partial durations then skew every histogram.

Map cancellation to CANCELED, and rethrow unchanged so structured concurrency still works:

```kotlin
try {
    val result = block(span)
    span?.end(SpanResult.SUCCESS)
    return result
} catch (e: CancellationException) {
    span?.end(SpanResult.CANCELED)   // not a failure; its partial duration isn't a measurement
    throw e
} catch (e: Throwable) {
    span?.end(SpanResult.FAILURE)
    throw e
}
```

### 2.3 A broad `catch (Exception)` inside the span body defeats 2.2

In Kotlin, `CancellationException` **is** an `Exception`. The common best-effort idiom —
`try { … } catch (_: Exception) {}` — therefore swallows the cancellation before the span wrapper
ever sees it, and the interrupted operation closes as SUCCESS with a partial duration. Having
fixed 2.2, this quietly un-fixes it.

Use a helper that swallows ordinary failures but lets cancellation through, anywhere inside a
span body.

### 2.4 A bare `return` inside a span closure returns from the closure

```swift
// WRONG — this exits the span's closure, not the journey function.
// The journey keeps running; only the span body stopped early.
trackSpan("product_view") { if shouldForceQuit { return } … }
```

Restructure as a value the closure returns and the caller checks *after* the span has closed.
This bit the demo's force-quit injection on both platforms.

### 2.5 Clock domain: monotonic uptime vs epoch

To back-date a cold-start root span to real process start you pass a custom start time. On
Android that time reaches `LogAttributesOverrides.OccurredAt(occurredAtTimestampMs)` — an **epoch**
timestamp. But the natural source, `SystemClock.uptimeMillis()`, is monotonic-since-boot. Passing
it through stamps the span's start log somewhere in 1970.

```kotlin
val processStartEpochMs =
    System.currentTimeMillis() - (SystemClock.uptimeMillis() - appStartUptimeMs)
```

iOS has no equivalent trap — process start is read from the kernel as a wall-clock `Date` — but it
has its own: capturing `Date()` in a stored static yields ~0, because Swift statics initialise
lazily on first access, i.e. at the moment TTI is computed rather than at launch.

Separately, custom times are **both-or-neither**: supply a custom start without a custom end and
the SDK tracks the span on system time, discarding the back-date entirely. The demo's root span
passes both (kernel process start, and `now` at end); its middle phases pass neither.

### 2.6 Explicit parent IDs, never an ambient span-context stack

Nest children by passing the parent's span ID down (`parentSpanId` on Android, `parentSpanID` —
capital ID — on iOS). It is tempting to keep a global "current span" stack instead so call sites
stay clean. Don't: screen loads run as independent, possibly concurrent tasks relative to the
journey's own coroutine, and a shared mutable stack will attribute a span to whatever happened to
be on top. The result is a plausible waterfall that is simply wrong.

Note that the SDK's own `trackSpan` wrapper does **not** forward a parent ID even where
`startSpan` accepts one — which is one of the three reasons to add a small helper (§3).

### 2.7 The span exists, but the app's default configuration never runs it

The demo's journey spans were added to the full-journey code path. The app was running a
*simplified* journey path, which has its own call sites. Three charts stayed empty for days.
Nothing was broken — the spans were real, the workflow was LIVE, the matchers were correct, and
the code they were in never executed.

Same class of problem, different cause: spans behind an off-by-default feature flag. The
recommendation-engine spans only fire when a "Rec v2" flag is on, and nothing in the automated
loop turns it on, so those charts look broken until someone flips it manually. If a span is gated,
provide a headless way to enable it and write that down next to the chart.

**Instrument every code path the default configuration actually runs**, and treat an empty chart
as "prove the code path executes" before "prove the matcher is right."

### 2.8 Chart-side defaults that make correct data unreadable

- **`y_axis.unit`** — set to `MILLISECONDS` at workflow *creation*. Left unset, a duration chart
  renders raw unitless numbers (`1.4K`, `2K`) and the reader has to guess. Fixable live afterwards
  as chart metadata, but it's free to get right up front.
- **`TimeSeriesMetadata.title`** — set one per series. Without it the legend and tooltips fall back
  to the raw aggregated action ID, an opaque hash string, which makes a multi-series comparison
  chart unreadable at exactly the moment it's most useful.
- **`_result != canceled`** — add this to the match rule for spans where cancellation is routine
  (per-row image loads, anything tied to scroll). Spans where cancellation is rare don't need it;
  filtering everywhere isn't worth resetting evaluation windows over.
- **Distinguishing fields aren't automatic.** A field like `retried` on a payment span is there
  for ad-hoc filtering; the default comparison chart still lumps retries and first attempts into
  one series unless you group by it.

---

## 3. Why a helper file, not raw `trackSpan`

Add a small per-platform bridge (the demo calls it `CaptureBridge`) rather than calling the SDK
wrapper at every site. Three concrete gaps, all of which bite on a real journey:

1. **No parent forwarding** — `startSpan` accepts a parent ID; `trackSpan` doesn't pass one, so
   nothing wrapped in it can nest under a journey span.
2. **Not async/suspend-capable** — its block is synchronous, and essentially every screen-load and
   journey-phase span wraps suspending or `async` work.
3. **Cancellation → FAILURE** — §2.2.

The helper is also the single place to fix §2.2, §2.3, and §2.5 once instead of at twenty call
sites.

**React Native has no span API at all.** The demo emulates one: paired start/end logs correlated
by a `_span_id` field, the end log carrying `_duration_ms`, `_result`, and optionally
`parent_span_id` — the same data shape the dashboard queries, so workflows and charts are written
identically to the native platforms. Confirm the current RN surface via **bd-docs** before
assuming this is still necessary.

---

## 4. Two different durations — don't let one stand in for the other

| | What it measures | Includes user think time? |
|---|---|---|
| `measure_time_rule` between two screen events (what **bd-cuj** builds) | Wall clock from one journey step to the next | **Yes** |
| A span's `_duration_ms` | The app's own work inside that step | No |

A checkout step showing 5 seconds is a slow API call or a user reading a form, and only having
both numbers tells you which. Put both on the journey dashboard and label them distinctly —
"step duration (wall clock)" vs "screen load (work)". A reader who sees one will otherwise assume
it covers the other, and conclude the app is slow when users were thinking, or that users are slow
when the app was blocked.

---

## 5. A dividend: identical durations are a signal

While validating these charts, five unrelated screen-load spans reported the *same* p10 duration
to nine significant figures. Different operations do not coincidentally take identical time. The
cause was a backend IP that had drifted to another subnet: every API call failed on the same fixed
~10.1s timeout, and because the client swallowed errors, nothing looked broken — the app still
ran, still navigated, still completed journeys.

Per-screen spans found a total backend outage that the app's own error handling had hidden. That
is the argument for spanning every journey element rather than one hand-picked flow: a single span
shows you a number, and a set of them shows you when the number is a lie.
