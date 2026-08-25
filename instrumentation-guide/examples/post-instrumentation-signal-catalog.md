# Post-instrumentation signal catalog

Use this with **bd-post-instrumentation** after exercising the app and before creating any
workflows or dashboards. Values in this template are examples; replace them with values observed
through Timeline, Issues, and `bd-cli` reads. This is evidence, not a source-code inventory.

The skill is read-only: it must not create, update, deploy, or delete account resources. Hand this
completed catalog to **bd-observability-portfolio** only after account-write authorization.

```yaml
observed_window: <UTC start → end>
app: <app/project>
representative_sessions:
  - id: <session id>
    journey: <flow exercised>
    evidence: <Timeline link or bd-cli read command>

journey:
  name: <checkout|onboarding|login>
  observed_steps:
    - value: <exact screen/event value>
      order: 1
      alternatives: []
      paired_span: <exact span name + observed result values>
  branches:
    - <steps that require an or_matcher>

signals:
  logs: [<exact stable messages>]
  spans: [<exact names + results>]
  network_paths: [<stable path templates>]
  fields: [<field = observed values>]
  entities: <present|absent + evidence>
  replay: <present|absent + evidence>

issues:
  observed: <yes|no>
  report_types: [<types>]
  symbolication: <readable|not verified|missing>
  classification_fields: [<only fields actually present>]

gaps:
  - signal: <missing or malformed signal>
    disposition: <repair instrumentation|exercise traffic|replace optional panel>
```

Do not turn a missing item into a matcher. A missing crash should be recorded as `observed: no`,
not simulated or classified speculatively. In that case, the portfolio skill may use only a
`bd schema`-confirmed generic crash/report condition for its baseline crash workflows.
