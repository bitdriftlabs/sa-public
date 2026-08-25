# Crash-workflow (Ripsaw/BDRL) examples — from a real fix, not hypothetical

These two scripts are the **actual, real BDRL** running live today for `ai.bitdrift.shop`
(Android), pulled verbatim from the checked-in workflow JSON in
[`bitdrift-shop/android/workflows/`](../../bitdrift-shop/android/workflows/). They're included
here as worked examples for [Step 20](../INSTRUMENTATION_GUIDE.md#20-build-workflows-and-dashboards-from-observed-data)
because a live-account audit found both had drifted — deployed with an **empty** `issue_match`
instead of this logic — and they were fixed as part of this guide's validation pass.

That drift is itself the lesson: a workflow can sit in a LIVE state, look healthy in the
workflow list, and still be matching *every* crash indiscriminately because its script never
made it to the platform. Verify the deployed script, not just the deployed state — run
`bd workflow describe <ID>` and confirm the `issue_match` body is actually there.

One deploy-time detail worth knowing if you copy these: the on-disk JSON key is
`bdrl_program`, but the current `bd workflow update` schema field is `program` (confirm via
`bd schema workflow.update IssueMatch` — don't assume the field name from an older example).

---

## Example 1 — classify a crash by which thread was holding a lock

Turns a generic `JVMCrash` into a lock-contention classifier: it isolates the crash type this
app specifically injects for lock contention, identifies which thread was holding the lock at
crash time, and — as a bonus, nearly free — cross-references memory pressure at the same
moment using the automatic memory snapshot every crash report carries (SDK 0.23.2+).

```
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

**Why this shape, generically:** `abort` early on any crash type you don't care about — this
keeps the chart clean (only lock-contention crashes get a `blocking_thread` value at all,
everything else is excluded from the match rather than showing up as `unknown`). The
`known_threads` allowlist is the part you'd customize per app — swap in your own app's known
lock-holding thread names.

---

## Example 2 — attribute a crash to a vendor SDK by scanning the stack trace

Scans every stack frame across every error in the crash report for a vendor SDK's package
prefix, and tags the crash with which vendor (if any) owned the frame that likely caused it —
turning "we don't know if this is our bug or a 3rd-party SDK's" into a standing chart.

```
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

**Why this shape, generically:** `flatten(map(...) -> filter(...))` is the standard pattern for
"scan every frame of every error for something." The important guardrail is the comment on
`vendor_reason` — only add a field straight from crash text if the value space is small and
bounded (here: exactly 2 possible vendor reasons); free-text fields from user-controlled or
3rd-party data can blow past bitdrift's cardinality limits (~1,000 group-by dims/30min) and get
silently dropped. Swap `com.adsdk.`/`com.analytics.fake.` for your own app's actual 3rd-party
SDK package prefixes.

---

## Reference

- [Ripsaw/BDRL scripting docs](https://docs.bitdrift.io/product/workflows/scripting/overview)
- The **bd-cli** skill's IssueMatch recipes (`recipes/issue-match.md`, `issue-match-examples.md`,
  `issue-match-metrics.md`) — for writing new Ripsaw scripts from scratch. These were previously a
  standalone `bd-issue-match` skill; it no longer exists as one.
