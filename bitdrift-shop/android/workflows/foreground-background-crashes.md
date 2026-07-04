# Foreground vs. Background Crash Workflows

Two workflows — `bd-shop-06-crash-foreground.json` and `bd-shop-07-crash-background.json` —
that split crash volume by whether the app was in the foreground or backgrounded at the
moment it crashed.

## Why

The crash-loop simulator (`SimulationManager.maybeFireCrash()`) gives every crash an
independent 50% chance of firing after sending the app to the background via
`moveTaskToBack(true)`, rather than always crashing in the foreground like before. That
makes "foreground vs. background" a real dimension in the crash data, not just a
theoretical one — these two workflows are how you observe it on a chart instead of
reading it off individual issue reports one at a time.

They're deliberately two separate workflows rather than one workflow with a `group_by`
dimension (compare to `bd-shop-03-crash-analytics.json`, which uses a single step +
`group_by` for crash *type*). Foreground/background here isn't a categorical breakdown of
one event stream so much as two independently interesting counters people tend to want on
their own chart/alert — keeping them separate also made the underlying "how do you even
express background on Android" problem (below) easier to reason about and fix
independently while debugging BDRL against real data.

## The platform constraint that shapes both scripts

Android's `app_metrics.running_state` (the field these scripts read) has **no
`"background"` value**. The only documented values are:

- `foreground`
- `foreground_service`
- `perceptible`

There is no literal to test for "background" directly. Both scripts work around this by
defining background as "anything that is not exactly `foreground`" — which is also why the
word `"foreground"` necessarily appears in *both* scripts, including the one whose entire
job is to count background crashes. That's expected, not a bug: it's the only concrete
enum value the platform gives you to compare against.

**How IssueMatch matching actually works — read this before either script below.**
`IssueMatch` is a filter, not a query: every crash report runs through the `bdrl_program`,
and `abort` is the *only* way to reject one. Whatever does **not** hit `abort` is a "match,"
and that's what fires the workflow's downstream actions (the counter, here). So a BDRL
matching script only ever needs to define what to *reject* — the counter automatically
picks up the complement, i.e. everything that survives.

That means the condition inside `if { abort }` is always the exclusion condition, the
inverse of what actually gets counted — which reads backwards if you're scanning for "what
does this count." Both scripts below name the positive concept first (`is_foreground` /
`is_background`) and phrase the `abort` as "reject anything that is NOT that," so the
comparison you'd intuitively expect to see in each workflow (`== "foreground"` in the
foreground one, `!= "foreground"` in the background one) is the first thing on the page,
and the `abort` line reads as a plain-English consequence of it rather than a condition you
have to mentally invert.

## `bd-shop-06-crash-foreground.json`

Counts crashes where `running_state == "foreground"` exactly.

```bdrl
# IssueMatch is a filter: every crash report runs through this script, and
# abort is the only way to reject one. Whatever does NOT hit abort "matches"
# and fires the downstream counter action. So this script only needs to
# define what to reject (not foreground) -- everything that survives is
# foreground, and that's exactly what the counter picks up.
#
# The parallel "Crashes in Background" workflow (bd-shop-07) counts everything
# that is NOT this exact state (foreground_service, perceptible, or any
# other/unknown value) -- Android has no separate "background" literal.
state = string(.app_metrics.running_state) ?? ""
is_foreground = state == "foreground"

# Reject anything that is NOT foreground -- everything that survives (is
# foreground) matches, and the counter action fires for it.
if !is_foreground {
  abort
}
```

One action, `foreground-crash-count`: a plain count of everything that survives the
`abort` check — no `group_by`, since the point of this chart is the total, not a
breakdown.

## `bd-shop-07-crash-background.json`

Counts everything else: `foreground_service`, `perceptible`, or any other/unknown value.

```bdrl
# IssueMatch is a filter: every crash report runs through this script, and
# abort is the only way to reject one. Whatever does NOT hit abort "matches"
# and fires the downstream counter action. So this script only needs to
# define what to reject (not background) -- everything that survives is
# background, and that's exactly what the counter picks up.
#
# Android's app_metrics.running_state has NO "background" value -- the only
# documented values are "foreground", "foreground_service", and "perceptible".
# So is_background is defined as: running_state is present and is not
# "foreground" (foreground_service, perceptible, or any other/unknown value).
state = string(.app_metrics.running_state) ?? ""
is_background = state != "foreground"

# Reject anything that is NOT background -- everything that survives (is
# background) matches, and the counter action fires for it.
if !is_background {
  abort
}
```

Same shape as the foreground workflow, inverted condition: `background-crash-count`.

## Cross-checking against real data

`maybeFireCrash()` also tags every crash with a `crash_context` custom field
(`"foreground"` or `"background"`) recording what the *app itself* attempted, independent
of what the BDRL script observes from `app_metrics.running_state`. Since
`moveTaskToBack` doesn't guarantee the OS has demoted process importance the instant it's
called, comparing these two signals is the way to validate the settle-time constant
(`BACKGROUND_SETTLE_MS` in `SimulationManager.kt`) is actually long enough:

```bash
bd issue describe <group_id> <issue_id> -ojson --jq '.issue.report.fields'
```

Look for `crash_context` in the field list and compare it against which workflow
(`bd-shop-06` vs `bd-shop-07`) actually counted that crash. If they disagree often,
`BACKGROUND_SETTLE_MS` needs to be longer.

## Deploy

```bash
bd workflow create workflows/bd-shop-06-crash-foreground.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-06-crash-foreground.chart.json
bd workflow create workflows/bd-shop-07-crash-background.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-07-crash-background.chart.json
```

### Optional: clearer graph-node titles

The chart-metadata above titles the *chart panel*. If you also want the workflow graph's
match-rule node to read clearly instead of showing the raw BDRL condition, apply this as
workflow-level metadata (a separate mechanism from chart metadata — see
`WorkflowMetadata.per_rule_metadata`):

```bash
cat > /tmp/bd-shop-06.metadata.json <<'EOF'
{
  "description": "Counts crashes reported while ai.bitdrift.shop was running in the foreground (app_metrics.running_state == 'foreground'), split out from the parallel 'Crashes in Background' workflow to compare foreground vs. background crash volume during crash-testing.",
  "per_rule_metadata": [
    { "rule_id": "foreground-crash", "title": "Foreground (running_state == foreground)" },
    { "rule_id": "foreground-crash-count", "title": "Foreground crash count" }
  ]
}
EOF
bd workflow update --workflow-id <ID> \
  --workflow-file workflows/bd-shop-06-crash-foreground.json \
  --metadata-file /tmp/bd-shop-06.metadata.json
```

Mirror the same pattern for `bd-shop-07` with `background-crash` / `background-crash-count`
rule IDs and inverted wording.
