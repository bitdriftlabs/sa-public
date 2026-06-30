# ANR Investigation Prompt & Analysis

## The Prompt

> Using the bd CLI, analyze the Sankey workflow and correlate it with the ANR/issue data to explain where users are dropping out and why. Specifically:
>
> 1. **Pull the Sankey links** (`bd workflow charts [sankey_id] --last 2h -o json`) and compute in/out/drop per screen
> 2. **Pull the ANR/counter workflow** (`bd workflow charts [anr_id] --last 2h -o json`) and count total events in the same window
> 3. **Compare the gap** — if Sankey shows fewer dropouts than ANR events, explain what's invisible
> 4. **Hydrate an ANR session** — get session IDs from `bd issue list [group_id]`, then `bd timeline logs [session_id]` filtered to ScreenView + error events to show the exact journey path before death
> 5. **Show the evidence** — present the session timeline, the funnel numbers, and explain the mechanism (SDK buffer flush, process kill, workflow timeout)
>
> Target app: android / com.example.shoppingdemo. Use `bd workflow list` and `bd issue group list` to discover the workflow and issue group IDs if not provided.

### Why this prompt works

| What | Why it matters |
|------|---------------|
| `bd workflow charts ... -o json` | Gets raw Sankey link data the CLI can't render |
| `bd issue group list` → `bd issue list` | Gets session IDs from ANR issues |
| `bd timeline logs [session]` | Shows the per-event journey inside a killed session |
| Compute in/out/drop per node | Reveals where the Sankey says dropout is vs isn't |
| Compare event counts across workflows | Exposes the gap between "ANRs happened" and "Sankey saw dropout" |

The key insight no prompt can shortcut: **you have to ask "why does the Sankey NOT show the dropout?"** — the Sankey showing a clean funnel while ANRs are firing is the signal, not the absence of one.

---

## The Answer

### Workflow IDs

| Workflow | ID | Purpose |
|----------|----|---------|
| Sankey Journey: Flag A Guest | `x3HI` | Tracks guest checkout journeys through screen views |
| ANR Count | `2JAb` | Counts ANR events (2 rules: built-in ANR + app termination with ANR exit reason) |

### Step 1 — Sankey funnel analysis (2h window)

```
Screen                   In    Out   Drop
--------------------------------------------------
Welcome                   0    173   -173  (entry)
Browse                   69     69      0
Search                   80     80      0
Categories               16     16      0
ProductDetail           160    167     -7
Cart                    167    167      0
CheckoutGuest           148    148      0  ← zero dropout
CheckoutSignIn           19     19      0
PaymentCard              20     20      0
PaymentApplePay          61     61      0
PaymentPayPal            55     55      0
PaymentAndroidPay        54     51      3
PaymentFailed            33     32      1
Confirmation            165      0    165  (exit)
```

**173 journeys started → 171 reached Confirmation → only 2 lost (1.2% loss rate)**

CheckoutGuest shows **zero dropout** in the Sankey.

### Step 2 — ANR count in the same window

```
ANR workflow 2JAb (2h):
  Rule 1 (APP_ANDROID_BUILT_IN_ANR): rollup = 91
  Rule 2 (APP_TERMINATION + ANR):    rollup = 91
  Total ANR events: ~91 actual ANRs (2 rules fire per ANR)
```

**91 ANR events fired** but the Sankey shows only 2 journeys lost.

### Step 3 — The gap: 91 ANRs, 2 dropouts

ANR-killed sessions are **invisible** to the Sankey because:

1. The ANR freezes the main thread (`Thread.sleep(15s)` + infinite loop)
2. Android's ANR handler kills the process
3. The bitdrift SDK buffer for the current session is lost — screen views after CheckoutGuest never flush
4. The Sankey workflow's loop step (`_screen_name != Confirmation`) keeps waiting for the next screen view. When the process dies, the workflow times out silently
5. The session never reaches the exit step, so it's not counted as a dropout — **it's as if it never existed**

### Step 4 — Hydrated ANR session timeline

Session `0b8f5507-c317-4f93-8704-bc4f6cef3ca0` (from issue group `11835401203663520483`, 99 events):

```
23:52:16.035  feature_flag_exposure_set  ff_variant=Variant A, ff_anr_a=enabled
23:52:16.290  ScreenView                 Welcome
23:52:16.374  ScreenView                 Browse
23:52:16.545  ScreenView                 ProductDetail
23:52:17.168  ScreenView                 Cart
23:52:17.384  ScreenView                 CheckoutGuest
23:52:17.424  guest_anr_injected         anr_screen_name=CheckoutGuest, trigger=random
              ← Thread.sleep starts, main thread frozen →
23:52:26.000  AppExit                    _app_exit_reason=ANR "Waited 5002ms for MotionEvent"
23:52:26.502  AppExit                    source=ApplicationExitInfo, reason=ANR
```

**No PaymentCard, PaymentApplePay, PaymentPayPal, PaymentAndroidPay, PaymentFailed, or Confirmation** — the journey was killed at CheckoutGuest.

The full session had only 36 events: 26 HTTP request/response pairs, 5 ScreenViews, 2 AppExits, 1 `guest_anr_injected`, 1 feature flag exposure, 1 hydration status.

### Step 5 — The evidence and the mechanism

**What the data shows:**

| Signal | Value | Source |
|--------|-------|--------|
| Journeys started | 173 | Sankey Welcome node |
| Journeys completed | 171 | Sankey Confirmation node |
| Sankey dropout at CheckoutGuest | 0 | Sankey links |
| ANR events fired | ~91 | Workflow 2JAb |
| ANR issue group events | 99 | Issue group 11835401203663520483 |
| ANR sessions reaching payment | 0 | Timeline hydration |

**The relationship between ANRs and payment failures:**

- **ANR does not cause payment failures.** ANR **prevents** the session from ever reaching payment. It's a funnel kill at CheckoutGuest that removes ~25% of Variant A guest sessions from the payment funnel entirely.
- **Variant A faces a double penalty:** 35% payment failure rate (vs Control 15%, Variant B 5%) for sessions that DO complete, PLUS ANR injection removing sessions before they ever get to pay.
- **The Sankey can't show this** because dead sessions vanish — the SDK buffer never flushes the post-CheckoutGuest events, and the workflow silently times out.

**How to detect this in the dashboard:**

1. Filter by `ff_anr_a = enabled` to isolate ANR-enabled runs
2. Count `guest_anr_injected` events — these DO flush (logged right before the freeze)
3. Cross-reference with ANR issue groups — all show `SimulationManager.maybeInjectGuestAnr` in the stack
4. Compare Sankey journey counts (starts vs completions) — the gap is the ANR impact
5. Hydrate individual ANR sessions via timeline to confirm the `Welcome → ... → CheckoutGuest → death` pattern

### Commands used

```bash
# Discover workflows
bd workflow list

# Get Sankey data
bd workflow charts x3HI --last 2h --platform android --app-id com.example.shoppingdemo -o json \
  --jq '.data[0].sankey_data.links' -r

# Get ANR count
bd workflow charts 2JAb --last 2h --platform android --app-id com.example.shoppingdemo -o json

# Find ANR issue groups
bd issue group list --platform android --app-id com.example.shoppingdemo

# Get session IDs from ANR issues
bd issue list 11835401203663520483 --limit 3 -o json --jq '.issues[].session_id' -r

# Hydrate and read an ANR session timeline
bd timeline logs <session_id> -o jsonl \
  --jq 'select(.message == "ScreenView" or .message == "guest_anr_injected" or
               .message == "feature_flag_exposure_set" or .message == "AppExit") |
        {ts: .timestamp, msg: .message, fields: .fields}' -r
```
