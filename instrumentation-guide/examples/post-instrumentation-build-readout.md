# Post-instrumentation build readout

This template turns an observed signal catalog into an account-side portfolio and verification
record. The required outcome is at least 10 focused workflows (at least 3 crash/Issue workflows)
and 5 populated dashboards. Replace unavailable optional panels with other observed signals;
never ship an empty dashboard.

| Artifact | Observed-data basis | Result | Post-deploy proof |
|----------|---------------------|--------|-------------------|
| Baseline crash/affected-user workflow | Schema-confirmed generic crash/report condition | Created | Workflow ID, LIVE status |
| Crash breakdown workflow | Schema-confirmed app version/platform field | Created | Workflow ID, LIVE status |
| Crash IssueMatch classifier | Observed Issue schema; safe generic report metadata if no crash was observed | Created | Workflow ID, deployed definition, LIVE status; note if no matching crash occurred |
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
