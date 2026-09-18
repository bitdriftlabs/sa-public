# Instrument a "foreground session" span (Android + iOS)

**Goal:** one bitdrift span that opens when the app enters the foreground and closes
when it leaves, so session duration can be charted as a histogram (P50/P90/P99).

This is independent of your existing session strategy / `session_id` — don't change
that. It's a plain manual span, matched by its own name.

**Validated end-to-end** on both platforms in bitdrift's own `bitdrift-shop` demo
apps (Android `AppLifecycleCallbacks.kt`, iOS `BitdriftShopApp.swift`) — spans and
`_duration_ms` confirmed flowing, workflow charting confirmed against real
foreground/background cycling.

**Works the same with `SessionStrategy.Fixed()`.** The span is driven purely by
OS-level lifecycle callbacks (`onActivityStarted`/`onActivityStopped`,
`didBecomeActive`/`willResignActive`), which fire on every foreground/background
transition regardless of session strategy. With `Fixed`, every log in a run still
carries the same `session_id`, but you'll still get a fresh `foreground_session` span
(start, end, `_duration_ms`) on every single background/foreground cycle — the two
mechanisms don't interact.

## Steps

1. Check whether the app already has an app-lifecycle listener:
   - **Android:** an existing `Application.ActivityLifecycleCallbacks` implementation,
     or a `ProcessLifecycleOwner` observer.
   - **iOS:** an existing `UIApplication`/`UIScene` notification observer, or
     lifecycle methods on `AppDelegate`/`SceneDelegate`.

   If one exists, add the span logic there. If not, create a minimal one.

2. **Android:** track a foreground activity count.
   - On the transition from 0→1 activities started, call
     `Logger.startSpan("foreground_session", LogLevel.INFO)` and hold the returned
     `Span`.
   - On the transition from 1→0 (all activities stopped), call
     `span.end(SpanResult.SUCCESS)`.

   ```kotlin
   class ForegroundSessionSpan : Application.ActivityLifecycleCallbacks {
       private var activityCount = 0
       private var span: Span? = null

       override fun onActivityStarted(activity: Activity) {
           activityCount++
           if (activityCount == 1) {
               span = Logger.startSpan("foreground_session", LogLevel.INFO)
           }
       }

       override fun onActivityStopped(activity: Activity) {
           activityCount--
           if (activityCount == 0) {
               span?.end(SpanResult.SUCCESS)
               span = null
           }
       }
       // other overrides can be no-ops
   }
   ```
   Register in `Application.onCreate()`:
   `registerActivityLifecycleCallbacks(ForegroundSessionSpan())`.

3. **iOS — SwiftUI apps (preferred if your app already uses `scenePhase`):**
   `.onChange(of: scenePhase)` also reports `.inactive` on transient
   interruptions (control centre, incoming call, notification banner) — only
   start/end the span on a real edge into/out of `.active`, or you'll get
   spurious extra spans.

   ```swift
   @main
   struct MyApp: App {
       @Environment(\.scenePhase) private var scenePhase
       @State private var lastPhase: ScenePhase?
       @State private var span: Span?

       var body: some Scene {
           WindowGroup {
               ContentView()
                   .onChange(of: scenePhase) { phase in
                       defer { lastPhase = phase }
                       switch phase {
                       case .active where lastPhase != .active:
                           span = Logger.startSpan(name: "foreground_session", level: .info)
                       case .background where lastPhase != .background:
                           span?.end(.success)
                           span = nil
                       default:
                           break
                       }
                   }
           }
       }
   }
   ```

   **iOS — UIKit apps (`AppDelegate`/no `scenePhase`):** bracket the span with
   app active/resign notifications instead (use the `UIScene` equivalents —
   `sceneDidBecomeActive` / `sceneWillResignActive` — if the app is
   scene-based without SwiftUI).

   ```swift
   NotificationCenter.default.addObserver(
       forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
   ) { _ in
       span = Logger.startSpan(name: "foreground_session", level: .info)
   }
   NotificationCenter.default.addObserver(
       forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
   ) { _ in
       span?.end(.success)
       span = nil
   }
   ```

4. Use the exact span name `foreground_session` on both platforms — that's what the
   bitdrift workflow will match on.

5. **Verify:** build and run the app, background/foreground it a couple of times,
   confirm in bitdrift (Timeline or Tail) that a `foreground_session` span with a
   `_duration_ms` field appears on backgrounding.

## Report back

- Which file(s) you added this to (or which existing lifecycle listener you extended).
- Confirmation that step 5's verification passed — include what you saw in
  Timeline/Tail.

## Why a span, not two plain logs

A span's end log carries `_duration_ms` on itself, so charting duration is a
single-step histogram match on that end log — no correlating two separate log lines
(e.g. a "foreground" log and a "background" log) across a multi-step workflow. That
correlation approach was tried and is unreliable at real usage volume: matching a
plain "app went to background" log against a job matcher across multiple in-flight
workflow runs doesn't stay 1:1 pairs the way a self-contained span duration does.
