# Post-instrumentation build readout

This is a reusable template. The Android/iOS observations below are a case study; replace them
with the target app's Step 19 catalog and do not treat the IDs or signal names as universal.

Use this with **bd-observability-portfolio** after **bd-post-instrumentation** has produced a
validated signal catalog and the user has authorized account writes. It turns the catalog into an
account-side portfolio and verification record. The required outcome is at least 10 focused
workflows (at least 3 crash/Issue workflows) and 5 populated dashboards. Replace unavailable
optional panels with other observed signals; never ship an empty dashboard.

Crash-specific panels may legitimately await matching traffic in a crash-free window. Keep
Stability and Crash Triage useful with populated application-health, release, session, network, or
other observed operational panels, and state which crash panels are awaiting traffic.

| Artifact | Observed-data basis | Result | Post-deploy proof |
|----------|---------------------|--------|-------------------|
| Baseline crash/affected-user workflow | Schema-confirmed generic crash/report condition | Created | Workflow ID, LIVE status |
| Crash breakdown workflow | Schema-confirmed app version/platform field | Created | Workflow ID, LIVE status |
| Crash classification workflow | Observed Issue schema; schema-confirmed generic crash/report condition only in a crash-free window | Created | Workflow ID, deployed definition, LIVE status; note if no matching crash occurred |
| CUJ funnel + conversion workflow | Exact Step 19 journey values and session IDs | Created | Workflow ID, LIVE status, exercised-session data |
| Screen-load / TTI / network / business-event workflows | Observed spans, paths, and logs | Created | IDs, chart metadata, non-zero data |
| Stability + Crash Triage dashboards | Crash workflow portfolio | Created | Dashboard IDs and populated panel list |
| Business/UX + Performance & Network dashboards | CUJ, spans, TTI, jank, network signals | Created | Dashboard IDs and populated panel list |
| Support & Sessions dashboard | Entities or session/log/network triage signals | Created | Dashboard ID and populated panel list |

For an unavailable optional panel, state the precise missing signal and its replacement. For example:

> Replaced the ANR-reason classifier with a crash breakdown by the observed app-version field:
> no representative ANR report was observed in the catalog. The baseline crash workflows remain
> deployed and await matching crash traffic.

For non-crash artifacts, re-exercise the journey after deployment. A LIVE workflow with no
matching journey data is a verification failure, not evidence of 0% conversion.

Validate chart scope before diagnosing missing ingest. The canonical first check is
`bd workflow charts <ID> --last 1h`; an explicit platform/app filter can be narrower than the
workflow's deployed target and make a populated workflow appear empty. Record both the unfiltered
result and any narrowed query used in the readout.

## Non-crash validation variant

When crash testing is deferred, run the Android infinite simulation with persisted crash, ANR,
and force-quit flags disabled. Report ordinary signal results separately from crash workflows.
In the latest Android and iOS POC passes, non-crash business/network activity was exercised, while
span-based workflows were `LIVE` but empty because the demo apps did not have real span call sites
(Android's helper was a no-op; iOS had no `startSpan`/`end` calls). That is an instrumentation gap,
not evidence that the journey had no traffic. Repair the span call sites, rerun the simulation, and
re-check chart series before treating those examples as validated.

Record every workflow, alert, and dashboard ID in this readout. Cleanup must remove the complete
portfolio, not only the crash and CUJ resources.
