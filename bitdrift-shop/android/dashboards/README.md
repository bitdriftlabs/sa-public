# bitdrift-shop Dashboards

Ready-to-deploy dashboard JSON payloads for the bitdrift-shop Android demo app, composing charts
from the workflows in [`../workflows/`](../workflows/) into curated dashboard views. See
[Dashboards: Overview](https://docs.bitdrift.io/product/dashboards/overview) for the underlying
product concept.

## Why these are structured differently from workflows

Workflow JSON files ([`../workflows/`](../workflows/)) are self-contained -- `bd workflow create`
builds a brand-new workflow from scratch, so the file never references anything that has to already
exist. Dashboards are the opposite: a dashboard chart is a *reference* to a chart that already lives
on a deployed workflow (`chart_id.workflow.workflow_id` + `chart_rule_id`), so a dashboard payload is
only valid once the workflow it points at has been created and has a real ID.

Every `workflow_id` in these files is therefore a placeholder --
`"__BD_SHOP_12_WORKFLOW_ID__"` -- not a real ID. Deploying substitutes the real, currently-deployed
workflow ID for that placeholder before calling `bd dashboard create`. Don't hardcode a real workflow
ID into these files; it will only be correct for whichever account happened to produce that ID.

## Deploy

**1. Look up the real workflow ID** by name (stable across accounts/re-deploys, unlike the ID
itself):

```bash
WORKFLOW_ID=$(bd workflow list -ojson --jq \
  '[.workflows[]? // .items[]? | select((.workflow.name // .name) == "bd-shop — Metric Grouping (Waveforms + Latency by Version)")][0] | (.workflow.id // .id)' -r)
echo "$WORKFLOW_ID"
```

If this comes back empty, deploy `bd-shop-12-metric-grouping.json` first -- see
[`../workflows/README.md`](../workflows/README.md).

**2. Substitute the placeholder and create the dashboard:**

```bash
python3 -c "
import json, sys
path, wf_id = sys.argv[1], sys.argv[2]
data = json.load(open(path))
raw = json.dumps(data).replace('__BD_SHOP_12_WORKFLOW_ID__', wf_id)
print(raw)
" dashboards/bd-shop-01-metric-grouping.json "$WORKFLOW_ID" > /tmp/bd-shop-01-metric-grouping.resolved.json

bd dashboard create --request-file /tmp/bd-shop-01-metric-grouping.resolved.json --open
```

`--open` prints the dashboard URL and opens it in a browser. Without it, get the URL later with:

```bash
bd dashboard open <DASHBOARD_ID> -ojson --jq .url -r
```

### Updating an existing deployment

Re-run the same lookup + substitution, then pass `--id` (or the resolved file's own `id`, if you
saved the response) to `bd dashboard update` instead of `create`:

```bash
bd dashboard update <DASHBOARD_ID> --request-file /tmp/bd-shop-01-metric-grouping.resolved.json --open
```

**Layout settings are not optional in practice**, despite every field in `DashboardLayoutSettings`
being individually optional in the schema. Confirmed live against the real API: an empty
`"layout_settings": {}` is rejected (`missing x in layout settings`), text/divider stylistic
components additionally require an exact `row_span` (`3`, confirmed live -- other values are
rejected), and the platform uses a **12-column grid** (confirmed live -- charts here use
`column_span: 12` for full-width rows). This file's layout is a plain stacked list: a `row_span: 3`
banner at `y: 0`, then each chart full-width (`column_span: 12`) at `row_span: 4`, `y` incrementing
by 4 per chart. Drag-to-rearrange in **Edit Dashboard** mode after deploying if you want something
other than a stacked list; see
[Dashboards: Overview > Organizing the dashboard](https://docs.bitdrift.io/product/dashboards/overview#organizing-the-dashboard).

## Dashboards

| File | Name | Tabs | What it shows |
|------|------|------|----------------|
| `bd-shop-01-metric-grouping.json` | bd-shop — Metric Grouping | **Grouping**: work-latency average/histogram/table, grouped by `sim_app_version`. **Waveforms & CloudWatch Check**: the five ported waveform metrics + the counter consistency check. | See [../metric-demo.md](../metric-demo.md) |

`dashboard_variables: [{"field_key": "sim_app_version"}]` promotes that dimension to the dashboard
header (**Collected Dimensions**), so viewers can filter the whole dashboard to a single simulated
version without editing any individual chart.

## Other lifecycle commands

```bash
bd dashboard list --query "bd-shop" -ojsonl --jq '{id, name, owner_name}'
bd dashboard get <DASHBOARD_ID> -ojson
bd dashboard favorite <DASHBOARD_ID>
bd dashboard delete <DASHBOARD_ID>
```

**Note:** `bd dashboard get` does not return `layout_settings` in its response. If you need to
re-update a dashboard's charts later, start from this repo's JSON (with the workflow ID
substituted), not from a `get` dump -- reconstructing layout from `get` will drop it.

## Span-timing dashboards

Four dashboards composing the `bd-shop-20`–`23` span-timing workflows (see
[`../workflows/README.md`](../workflows/README.md#span-timing-workflows-bd-shop-20-through-bd-shop-23)),
one per coherent question, and deliberately mirroring the iOS app's equivalents:

| File | Live id | Backing workflow |
|---|---|---|
| `android-cold-start-span-timings.dashboard.json` | [`cQJTUdHJ3NQsm_H1NVsgf`](https://explorations.bitdrift.io/dashboards/cQJTUdHJ3NQsm_H1NVsgf) | `RLXS` |
| `android-screen-load-timings.dashboard.json` | [`XpcvEcjfYuZU9GdgvYvtG`](https://explorations.bitdrift.io/dashboards/XpcvEcjfYuZU9GdgvYvtG) | `vokX` |
| `android-journey-subphase-timings.dashboard.json` | [`TdQHRtJe305Xjz4lEVV4h`](https://explorations.bitdrift.io/dashboards/TdQHRtJe305Xjz4lEVV4h) | `GfJa` |
| `android-recommendation-engine-timings.dashboard.json` | [`b8_b4FFF8xzstrR0b9Psg`](https://explorations.bitdrift.io/dashboards/b8_b4FFF8xzstrR0b9Psg) | `joJr` |

Each file's chart components reference its backing `workflow_id` above, so on a
fresh account **edit that id before running `bd dashboard create`, not after** — the
committed files otherwise produce dashboards pointing at this account's workflows.

Two API quirks worth knowing, both learned the hard way on the iOS side:

- **`bd dashboard update` is not a safe way to edit these.** It requires each chart
  component's `id` to be the server-assigned *numeric* id rather than the string id
  used at creation; getting that wrong emptied a dashboard's entire charts array
  while still reporting `SUCCESS`. Delete and recreate instead.
- **Set `y_axis.unit` at creation.** Omitting it renders duration charts as bare
  numbers (`1.4K`) with no unit; these were all created with `MILLISECONDS`.
