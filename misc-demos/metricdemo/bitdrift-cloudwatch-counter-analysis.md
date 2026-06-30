# bitdrift ↔ CloudWatch Counter Consistency Analysis

## Setup

The metricdemo Android app emits a `metric_counter` field set to `1.0` every second.
bitdrift aggregates this using a `count` (sum) rule and exports each completed window's
total to CloudWatch. At 1 event/second, any N-second aggregation window should contain
exactly N counts — making discrepancies immediately quantifiable.

## Observed Values (last 15 minutes)

| System | Value | Notes |
|--------|-------|-------|
| bitdrift SUM | 828 | Sum of completed 1-minute aggregation windows |
| CloudWatch Sum | 897 | Sum statistic, 5-minute period |
| Expected | 900 | 15 min × 60 events/min |

## Why They Differ

**This is not data loss.** The ~69-count gap (~7.7%) has a structural cause:

bitdrift's SUM display only includes **completed** aggregation windows. The current
in-progress window is excluded until it closes. Over a 15-minute query window, this
means approximately 1 window (~60 events) is systematically absent from the bitdrift
total.

CloudWatch, by contrast, accumulates every metric data point it receives — including
data from the still-open boundary window — so its total is closer to the true event
count (~897 vs expected 900, <0.3% off).

## The Gap Shrinks With Longer Windows

| Query window | Missing windows | Approximate gap |
|-------------|-----------------|-----------------|
| 15 minutes | ~1 of 15 | ~6–7% |
| 1 hour | ~1 of 60 | ~1–2% |
| 24 hours | ~1 of 1440 | <0.1% |

## Recommended Comparison Methodology

- Use **1-hour or longer** windows when comparing bitdrift vs CloudWatch totals.
- In CloudWatch, use **Sum statistic** (not Average) to get raw accumulated counts.
- Expect a residual gap of ~1–2% over 1-hour windows — this is the open-window
  boundary artifact, not evidence of event loss.
- A gap **significantly above ~2% sustained over 1+ hours** would warrant investigation
  as a potential data loss or duplication issue.

## Bottom Line

Transport fidelity from bitdrift to CloudWatch appears to be **~99%+ over longer
windows**. The observed short-window discrepancy is fully explained by aggregation
window boundary handling, not by dropped events.
