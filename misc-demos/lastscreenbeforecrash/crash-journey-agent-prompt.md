# Agent prompt — "what path led to our crashes?"

Paste the block below to an agent with the **bd-cli** skill available. It reads
the screen shift register off individual crash reports and builds a ranked table
of the actual paths users took into a crash.

Why an agent rather than a chart: a workflow chart has to emit each path as a
metric dimension, and distinct paths blow past the cardinality budget (500
combinations per metric per interval) and silently collapse into an `other`
bucket. An agent reads reports one at a time, so it has no cardinality ceiling
and can use the full register depth, join against feature flags and app version,
and explain the reports that carry no path at all. Use the chart for the live
trend; use this for the analysis.

---

## The prompt

```
Using the bd CLI, build a ranked table of the user journeys that led to crashes
in <APP_ID> over <TIME RANGE>.

The app records a screen shift register as global fields, which ride onto the
crash report itself: `screen_current` is where the crash happened, and
`screen_prev_1` … `screen_prev_4` are the four screens before it, newest first.
The literal string "none" means that slot was never filled (the session was
shorter than the register), which is different from the field being absent.

Steps:

1. `bd issue group list --app-id <APP_ID> --platform apple --last <RANGE> -ojson`
   to get the crash groups.
2. For each group, `bd issue list <GROUP_ID> -ojson --limit <N>` to get the
   individual issue IDs and their `session_id`.
3. For each issue, `bd issue describe <GROUP_ID> <ISSUE_ID> -ojson`. The
   register is at `.issue.report.fields`, which is a LIST of `{key, value}`
   objects — not a map. Parse accordingly.
4. Reconstruct each path by reading `screen_prev_4` → `screen_prev_1` →
   `screen_current`, dropping any "none" entries. Render it as
   `Welcome > Browse > ProductDetail`.
5. Aggregate identical paths and rank by count.

Report:

- A ranked table: path, count, % of total, and the distinct crash kinds
  (`.issue.reason`, e.g. EXC_BREAKPOINT) seen on that path.
- Which screen most often *precedes* the crash screen (`screen_prev_1`) — the
  single most actionable number, since it names the transition to investigate.
- Any reports carrying no register fields at all, counted separately and NOT
  mixed into the ranking. These are crashes the OS reported on the next launch,
  in a fresh process where no global fields were set yet. Correlate them against
  `.issue.reason` and say which crash kinds they cluster on.
- One or two `session_id` values per top path, so a human can open the full
  timeline as evidence.

Constraints — please respect these, they are easy to get wrong:

- Do not treat `session_count` on an issue group as "activity in the window". It
  is lifetime, and group listing can return groups whose activity falls entirely
  outside the requested range. Check `first_seen` / `last_seen` before claiming
  something is current.
- Do not present a path ranking without also reporting the no-register count.
  Omitting it silently overstates how much of the crash volume you explained.
- If a build changed the journey during the window, paths from before and after
  will both appear and should not be merged. Say so rather than averaging them.
```

---

## What good output looks like

```
Path                                        Count   %     Crash kinds
Welcome > Browse > ProductDetail              22   65%    EXC_BREAKPOINT
ProductDetail > Cart > CheckoutGuest           4   12%    EXC_BREAKPOINT, EXC_CRASH
Browse > ProductDetail > Cart                  2    6%    EXC_BREAKPOINT

Most common predecessor of a crash screen: Browse (22 of 34)

No register fields: 6 reports (18%) — 4 EXC_CRASH, 2 EXC_BREAKPOINT.
  OS-reported on next launch; no global fields existed yet. Expected.

Evidence: 4898C75F-375E-4030-BA33-941C193818A1 (top path)
```

The "no register fields" line is the one people leave out. Without it the
ranking looks like it covers everything, when it may only cover 80% of crashes.

## Verifying the register is actually populated

Before trusting any of this, confirm on one report:

```bash
bd issue describe <GROUP_ID> <ISSUE_ID> -ojson \
  | python3 -c "import json,sys; [print(f\"{e['key']:16} {e['value']}\") for e in json.load(sys.stdin)['issue']['report']['fields'] if 'screen' in e['key']]"
```

Expect `screen_current` plus four `screen_prev_N`. All `none` past
`screen_prev_1` means the crash fired too early in the journey for the register
to fill — the register is working, the journey is just short.
