#!/usr/bin/env python3
"""Deploy the bd-shop workflows and dashboards to a bitdrift account.

  tools/bd-deploy.sh <app_id> [options]      # plan only (dry run) by default

The source of truth is workflows/manifest.json. Workflows are found in the account by their exact
name, so running this is safe against an account that already has them: anything already there is
left alone ("exists"), only what is missing is created, and nothing is ever deleted. Dashboards are
matched by title and have `__WF_<key>__` placeholders resolved to the account's workflow IDs.

Options:
  --platform android|apple   which app's workflows to deploy (default: apple if the app id ends in
                             .ios, else android)
  --include-shared           also deploy workflows that target both platforms (foreground session
                             count/duration); skipped by default so each platform's command owns
                             only its own set
  --only KEY[,KEY...]        restrict to these manifest keys
  --update KEY[,KEY...]      replace the config of these EXISTING workflows (stop -> update ->
                             deploy). The workflow's accumulated data window restarts: ask first.
  --update-dashboards        update dashboards that already exist (non-destructive)
  --no-dashboards            workflows only
  --apply                    actually make the changes (otherwise only print the plan)
  --yes                      with --apply, do not prompt for confirmation
  --name-suffix S            append S to every workflow name and dashboard title (for trial runs
                             that must not touch the real ones)
  --check                    offline: validate manifest.json and the files it points at, then exit
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
WF = os.path.join(ROOT, "workflows")
DASH = os.path.join(ROOT, "dashboards")


def bd(*args):
    return subprocess.run(["bd", *args], capture_output=True, text=True)


def load_manifest():
    with open(os.path.join(WF, "manifest.json")) as f:
        return json.load(f)


def read(path):
    with open(path) as f:
        return f.read()


def render_workflow(w, manifest, app_ids, suffix=""):
    """Returns (json_text, metadata_path, chart_path) for one manifest entry."""
    defaults = manifest["apps"]
    if w.get("template"):
        text = read(os.path.join(WF, w["template"]))
        v = dict(w["vars"])
        v["app_id"] = app_ids.get(w["platform"], v["app_id"])
        for k, val in v.items():
            text = text.replace("{{%s}}" % k, val)
    else:
        text = read(os.path.join(WF, w["workflow"]))
        for plat, default in defaults.items():
            if app_ids.get(plat) and app_ids[plat] != default:
                text = text.replace('"app_id": "%s"' % default, '"app_id": "%s"' % app_ids[plat])
    obj = json.loads(text)
    if suffix:
        obj["name"] += suffix
        text = json.dumps(obj, indent=2, ensure_ascii=False) + "\n"
    meta = os.path.join(WF, w["metadata"]) if w.get("metadata") else None
    chart = os.path.join(WF, w["chart_metadata"]) if w.get("chart_metadata") else None
    return text, obj["name"], meta, chart


def check(manifest):
    errs = []
    keys = [w["key"] for w in manifest["workflows"]]
    names = [w["name"] for w in manifest["workflows"]]
    slugs = [(w["platform"], w["slug"]) for w in manifest["workflows"]]
    for what, vals in (("key", keys), ("name", names), ("slug+platform", slugs)):
        dup = {v for v in vals if vals.count(v) > 1}
        if dup:
            errs.append("duplicate %s: %s" % (what, sorted(map(str, dup))))
    apps = dict(manifest["apps"])
    for w in manifest["workflows"]:
        try:
            text, name, meta, chart = render_workflow(w, manifest, apps)
            if name != w["name"]:
                errs.append("%s: rendered name %r != manifest name %r" % (w["key"], name, w["name"]))
            if "{{" in text:
                errs.append("%s: unresolved {{placeholder}} after render" % w["key"])
            for p in (meta, chart):
                if p:
                    json.loads(read(p))
        except Exception as e:  # noqa: BLE001
            errs.append("%s: %s" % (w["key"], e))
    for d in manifest["dashboards"]:
        path = os.path.join(DASH, d["file"])
        if not os.path.exists(path):
            errs.append("dashboard %s: %s missing" % (d["slug"], d["file"]))
            continue
        tokens = set(re.findall(r"__WF_([A-Za-z0-9_]+)__", read(path)))
        if tokens != set(d["workflows"]):
            errs.append("dashboard %s: placeholders %s != declared workflows %s" % (d["slug"], sorted(tokens), sorted(d["workflows"])))
        for k in tokens - set(keys):
            errs.append("dashboard %s: placeholder for unknown workflow key %s" % (d["slug"], k))
    return errs


def live_workflows():
    r = bd("workflow", "list", "--all", "-ojson")
    if r.returncode != 0:
        sys.exit("bd workflow list failed: " + r.stderr.strip())
    out = {}
    for it in json.loads(r.stdout)["items"]:
        w = it["workflow"]
        out.setdefault(w["name"], []).append((w["id"], w.get("state")))
    return out


def live_dashboards():
    r = bd("dashboard", "list", "-ojson")
    if r.returncode != 0:
        sys.exit("bd dashboard list failed: " + r.stderr.strip())
    out = {}
    for x in json.loads(r.stdout).get("dashboards", []):
        c = x.get("custom_dashboard") or {}
        if c.get("title"):
            out.setdefault(c["title"], []).append(c["id"])
    return out


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("app_id", nargs="?")
    ap.add_argument("--platform")
    ap.add_argument("--include-shared", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--update", default="")
    ap.add_argument("--update-dashboards", action="store_true")
    ap.add_argument("--no-dashboards", action="store_true")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--yes", action="store_true")
    ap.add_argument("--name-suffix", default="")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("-h", "--help", action="store_true")
    a = ap.parse_args()
    if a.help:
        print(__doc__)
        return
    manifest = load_manifest()
    errs = check(manifest)
    if a.check:
        for e in errs:
            print("ERROR", e)
        print("manifest: %d workflows, %d dashboards, %d error(s)" % (len(manifest["workflows"]), len(manifest["dashboards"]), len(errs)))
        sys.exit(1 if errs else 0)
    if errs:
        sys.exit("manifest problems (run --check):\n  " + "\n  ".join(errs))
    if not a.app_id:
        sys.exit(__doc__)

    plat = a.platform or ("apple" if a.app_id.endswith(".ios") else "android")
    app_ids = dict(manifest["apps"])
    app_ids[plat] = a.app_id
    only = set(filter(None, (a.only or "").split(",")))
    updates = set(filter(None, a.update.split(",")))
    suffix = a.name_suffix

    wanted = [w for w in manifest["workflows"]
              if (w["platform"] == plat or (a.include_shared and w["platform"] == "both"))
              and (not only or w["key"] in only)]
    live = live_workflows()
    manifest_names = {w["name"] + sfx for w in manifest["workflows"] for sfx in ("", suffix)}

    print("account workflows: %d total | deploying %d for %s (app %s)%s\n" % (
        sum(len(v) for v in live.values()), len(wanted), plat, a.app_id, " [name suffix %r]" % suffix if suffix else ""))
    plan = []
    for w in wanted:
        text, name, meta, chart = render_workflow(w, manifest, app_ids, suffix)
        hits = live.get(name, [])
        if hits and w["key"] in updates:
            action = "update"
        elif hits:
            action = "exists"
        else:
            action = "create"
        plan.append(dict(w=w, text=text, name=name, meta=meta, chart=chart, action=action, id=hits[0][0] if hits else None,
                         state=hits[0][1] if hits else None, dup=len(hits) > 1))
        print("  %-7s %-44s %s%s" % (action.upper(), w["key"], (hits[0][0] + " " + str(hits[0][1])) if hits else "-",
                                     "  (!! %d live workflows share this name)" % len(hits) if len(hits) > 1 else ""))
    unknown = [u for u in updates if u not in {p["w"]["key"] for p in plan}]
    if unknown:
        sys.exit("--update names workflows that are not in this deploy set: %s" % unknown)
    for u in updates:
        if next(p for p in plan if p["w"]["key"] == u)["action"] != "update":
            sys.exit("--update %s: no such workflow in the account (it would be created, not updated)" % u)
    unmanaged = sorted(n for n in live if n.lower().startswith("bd-shop") and n not in manifest_names)
    if unmanaged:
        print("\nlive bd-shop workflows not managed by this manifest (left untouched):")
        for n in unmanaged:
            print("  -", n, live[n][0][0])

    dash_plan = []
    if not a.no_dashboards:
        ldash = live_dashboards()
        print("\ndashboards:")
        for d in manifest["dashboards"]:
            if d["platform"] != plat:
                continue
            title = d["name"] + suffix
            hits = ldash.get(title, [])
            have = {p["w"]["key"] for p in plan if p["action"] in ("exists", "update", "create")}
            missing = [k for k in d["workflows"] if k not in have and not any(
                m["key"] == k and live.get(m["name"] + suffix) for m in manifest["workflows"])]
            if missing:
                action = "skip (needs workflows %s)" % missing
            elif hits:
                action = "update" if a.update_dashboards else "exists"
            else:
                action = "create"
            dash_plan.append(dict(d=d, title=title, action=action, id=hits[0] if hits else None))
            print("  %-9s %-44s %s" % (action.split()[0].upper(), d["slug"], hits[0] if hits else "-"))

    creates = [p for p in plan if p["action"] == "create"]
    ups = [p for p in plan if p["action"] == "update"]
    dcreate = [p for p in dash_plan if p["action"] in ("create", "update")]
    print("\nplan: create %d workflow(s), update %d workflow(s), %d dashboard change(s); nothing is deleted." % (len(creates), len(ups), len(dcreate)))
    if not a.apply:
        print("dry run: re-run with --apply to make these changes.")
        return
    if not (creates or ups or dcreate):
        print("nothing to do.")
        return
    if ups:
        print("WARNING: updating %s restarts their data window (stop/update/deploy)." % [p["w"]["key"] for p in ups])
    if not a.yes:
        if input("proceed? [y/N] ").strip().lower() != "y":
            sys.exit("aborted.")

    ids = {}
    for p in plan:
        if p["id"]:
            ids[p["w"]["key"]] = p["id"]
    failures = 0
    tmp = tempfile.mkdtemp(prefix="bd-deploy-")
    for p in creates + ups:
        w = p["w"]
        wf = os.path.join(tmp, w["key"] + ".json")
        open(wf, "w").write(p["text"])
        extra = []
        if p["meta"]:
            extra += ["--metadata-file", p["meta"]]
        if p["chart"]:
            extra += ["--chart-metadata-file", p["chart"]]
        if p["action"] == "create":
            print("→ create %s" % w["key"])
            r = bd("workflow", "create", wf, *extra)
            m = re.search(r"Created workflow ([A-Za-z0-9]+)", r.stdout + r.stderr)
            if r.returncode != 0 or not m:
                print("    FAILED:", (r.stdout + r.stderr).strip()[:300]); failures += 1; continue
            wid = m.group(1)
            ids[w["key"]] = wid
            d = bd("workflow", "deploy", wid)
            print("    created %s%s" % (wid, "" if d.returncode == 0 else "  — DEPLOY FAILED: " + d.stderr.strip()[:200]))
            failures += d.returncode != 0
        else:
            wid = p["id"]
            print("→ update %s (%s)" % (w["key"], wid))
            steps = [("stop", ["workflow", "stop", wid]),
                     ("update", ["workflow", "update", "--workflow-id", wid, "--workflow-file", wf, *extra]),
                     ("deploy", ["workflow", "deploy", wid])]
            for label, cmd in steps:
                r = bd(*cmd)
                if r.returncode != 0:
                    print("    %s FAILED: %s" % (label, (r.stdout + r.stderr).strip()[:300])); failures += 1; break
            else:
                print("    updated and redeployed")
    for dp in dash_plan:
        if dp["action"] not in ("create", "update"):
            continue
        text = read(os.path.join(DASH, dp["d"]["file"]))
        for k in dp["d"]["workflows"]:
            if k not in ids:
                m = next(x for x in manifest["workflows"] if x["key"] == k)
                hits = live.get(m["name"] + suffix, [])
                if hits:
                    ids[k] = hits[0][0]
            if k not in ids:
                print("→ dashboard %s: workflow %s unresolved, skipping" % (dp["d"]["slug"], k)); failures += 1; break
            text = text.replace("__WF_%s__" % k, ids[k])
        else:
            obj = json.loads(text)
            if suffix:
                obj["name"] = obj["name"] + suffix
            rf = os.path.join(tmp, dp["d"]["slug"] + ".dashboard.json")
            json.dump(obj, open(rf, "w"), ensure_ascii=False)
            print("→ %s dashboard %s" % (dp["action"], dp["d"]["slug"]))
            r = bd("dashboard", "update", dp["id"], "--request-file", rf) if dp["action"] == "update" \
                else bd("dashboard", "create", "--request-file", rf)
            if r.returncode != 0:
                print("    FAILED:", (r.stdout + r.stderr).strip()[:300]); failures += 1
    print("\ndone with %d failure(s)." % failures)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
