# bitdrift-shop Dashboards

Dashboard JSON payloads that compose charts from the workflows in [`../workflows/`](../workflows/) into curated
views. Each file is a `bd dashboard create` request. See
[Dashboards: Overview](https://docs.bitdrift.io/product/dashboards/overview) for the product concept.

## Why they use placeholders

A dashboard chart is a *reference* to a chart that already lives on a deployed workflow (`workflow_id` +
`chart_rule_id`), so a payload is only valid once its workflows exist in the account. Every `workflow_id` in these
files is therefore a placeholder, `__WF_<key>__`, where `<key>` is the workflow's key in
[`../workflows/manifest.json`](../workflows/manifest.json). Never paste a real workflow ID into these files: it is
only correct for whichever account produced it.

## Deploy

```bash
tools/bd-deploy.sh ai.bitdrift.shop --apply        # Android set: workflows first, then dashboards
tools/bd-deploy.sh ai.bitdrift.shop.ios --apply    # iOS set
```

[`tools/bd-deploy.sh`](../tools/bd-deploy.sh) looks each workflow up by name, creates the missing ones, replaces the
placeholders with the account's real IDs, and creates a dashboard only if none with that title exists. Pass
`--update-dashboards` to update dashboards that already exist (dashboard edits do not reset any data). The manifest
lists which workflows each dashboard needs; a dashboard whose workflows are missing is skipped, not half-built.

To change a dashboard by hand: `bd dashboard get <id> -ojson`, edit, and keep the committed file's placeholders. Note
that `bd dashboard get` does not return `layout_settings`, so edit the committed payload rather than round-tripping
the response.

```bash
bd dashboard list -ojsonl --jq '{id, title}'    # what is in the account
bd dashboard open <DASHBOARD_ID>                # open one in the browser
```
