#!/usr/bin/env python3
"""Validate recorded telemetry streams (JSONL from each app's record mode) against spec/.

Usage: conformance.py --platform <android|ios|reactnative|flutter> [--runs N] FILE [FILE ...]
       conformance.py --self-test

Record line shapes are documented in android/.../Recorder.kt. Checks, per file:
  * every log message is a spec event for the platform (the `about_to_crash: <kind>` message
    form maps to the about_to_crash event), at the spec level (unless `drift_level` exempts it);
  * required fields are present; every field key is in the spec registry;
  * every span name is a spec span; each start has exactly one end; the parent span, when
    given, is the spec parent; the end result is one of the spec's results;
  * every screen view is a spec screen;
  * the autorun marker (sim_autorun_complete) appears once and matches --runs, and the
    stream holds that many journey_started events and journey spans.
Exit status is non-zero if any file has errors. Run through tools/codegen/.venv (needs PyYAML).
"""
import argparse
import json
import os
import sys

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def load_spec(name):
    with open(os.path.join(ROOT, "spec", name + ".yaml")) as f:
        return yaml.safe_load(f)


def applies(entry, platform):
    p = entry.get("platforms")
    return p is None or platform in p


class Spec:
    def __init__(self, platform):
        t = load_spec("telemetry")
        self.platform = platform
        self.events = {e["name"]: e for e in t["events"] if applies(e, platform)}
        self.spans = {s["name"]: s for s in t["spans"] if applies(s, platform)}
        self.fields = {f["key"] for f in t["fields"] if applies(f, platform)}
        self.fields |= {g["key"] for g in t.get("global_fields", []) if applies(g, platform)}
        self.screens = {s["name"] for s in load_spec("screens")["screens"] if applies(s, platform)}


def level_ok(spec_event, level, platform):
    want = spec_event.get("level")
    exempt = (spec_event.get("drift_level") or {}).get(platform)
    return want is None or want == level or exempt is not None


def event_for(message, spec):
    if message in spec.events:
        return message
    if message.startswith("about_to_crash") and "about_to_crash" in spec.events:
        return "about_to_crash"
    return None


def check(lines, spec, runs=None):
    errors, warnings = [], []
    open_spans = {}
    counts = {"journey_started": 0, "journey_spans": 0, "markers": 0, "logs": 0, "spans": 0, "screens": 0}
    marker = None
    for n, raw in enumerate(lines, 1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            r = json.loads(raw)
        except ValueError as e:
            errors.append(f"line {n}: not JSON ({e})")
            continue
        kind = r.get("kind")
        fields = r.get("fields") or {}
        for k in fields:
            if k not in spec.fields:
                errors.append(f"line {n}: field key '{k}' is not in the spec registry")
        if kind == "log":
            counts["logs"] += 1
            msg = r.get("message", "")
            name = event_for(msg, spec)
            if name is None:
                errors.append(f"line {n}: log message '{msg}' is not a spec event for {spec.platform}")
                continue
            ev = spec.events[name]
            if not level_ok(ev, r.get("level"), spec.platform):
                errors.append(f"line {n}: '{name}' logged at {r.get('level')}, spec says {ev.get('level')}")
            for req in ev.get("required") or []:
                if req not in fields:
                    errors.append(f"line {n}: '{name}' is missing required field '{req}'")
            if name == "journey_started":
                counts["journey_started"] += 1
            if name == "sim_autorun_complete":
                counts["markers"] += 1
                marker = fields
        elif kind == "span_start":
            counts["spans"] += 1
            name, sid = r.get("name"), r.get("id")
            sp = spec.spans.get(name)
            if sp is None:
                errors.append(f"line {n}: span '{name}' is not a spec span for {spec.platform}")
            elif r.get("parent") is not None:
                parent_name = (open_spans.get(r["parent"]) or {}).get("name")
                want = sp.get("parent")
                if want is not None and parent_name is not None and parent_name != want:
                    errors.append(f"line {n}: span '{name}' parented to '{parent_name}', spec says '{want}'")
            if sid in open_spans:
                errors.append(f"line {n}: span id {sid} started twice")
            open_spans[sid] = {"name": name, "line": n, "carried": bool(r.get("carried"))}
            if name == "journey" and not r.get("carried"):
                counts["journey_spans"] += 1
        elif kind == "span_end":
            sid = r.get("id")
            st = open_spans.pop(sid, None)
            if st is None:
                errors.append(f"line {n}: span_end for unknown or already-ended span {sid} ('{r.get('name')}')")
                continue
            sp = spec.spans.get(st["name"])
            res = r.get("result")
            if sp and sp.get("results") and res not in sp["results"] and res != "unknown":
                errors.append(f"line {n}: span '{st['name']}' ended '{res}', spec allows {sp['results']}")
        elif kind == "screen":
            counts["screens"] += 1
            if r.get("name") not in spec.screens:
                errors.append(f"line {n}: screen '{r.get('name')}' is not a spec screen for {spec.platform}")
        else:
            errors.append(f"line {n}: unknown record kind '{kind}'")
    for sid, st in open_spans.items():
        if st["carried"] or (spec.spans.get(st["name"]) or {}).get("long_lived"):
            continue  # started before recording began, or a span meant to outlive the run (foreground_session)
        errors.append(f"line {st['line']}: span '{st['name']}' ({sid}) never ended")
    if counts["markers"] != 1:
        errors.append(f"expected exactly one sim_autorun_complete, found {counts['markers']}")
    if runs is not None:
        if counts["journey_started"] != runs:
            errors.append(f"expected {runs} journey_started, found {counts['journey_started']}")
        if counts["journey_spans"] != runs:
            errors.append(f"expected {runs} journey spans, found {counts['journey_spans']}")
        if marker is not None and str(marker.get("total_runs")) != str(runs):
            errors.append(f"marker total_runs={marker.get('total_runs')}, expected {runs}")
    return errors, warnings, counts


def self_test():
    spec = Spec("android")
    good = [
        {"kind": "log", "level": "info", "message": "simulation_start", "fields": {"total_runs": "1"}},
        {"kind": "span_start", "id": "a", "name": "journey", "parent": None, "fields": {"variant": "Control"}},
        {"kind": "log", "level": "info", "message": "journey_started", "fields": {"run": "1", "variant": "Control"}},
        {"kind": "span_end", "id": "a", "name": "journey", "result": "success"},
        {"kind": "log", "level": "info", "message": "sim_autorun_complete",
         "fields": {"total_runs": "1", "sim_seed": "1", "persona": "control"}},
    ]
    errs, _, _ = check([json.dumps(x) for x in good], spec, runs=1)
    assert not errs, errs
    bad = [
        {"kind": "log", "level": "info", "message": "journey_start", "fields": {}},
        {"kind": "span_start", "id": "b", "name": "journey", "parent": None},
        {"kind": "log", "level": "info", "message": "payment_failed", "fields": {"payment_method": "card"}},
    ]
    errs, _, _ = check([json.dumps(x) for x in bad], spec, runs=1)
    joined = " | ".join(errs)
    for needle in ("journey_start", "never ended", "sim_autorun_complete"):
        assert needle in joined, (needle, errs)
    print("conformance self-test OK")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform")
    ap.add_argument("--runs", type=int)
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    if a.self_test:
        self_test()
        return
    if not a.platform or not a.files:
        ap.error("--platform and at least one FILE are required")
    spec = Spec(a.platform)
    bad = 0
    for path in a.files:
        with open(path) as f:
            errors, warnings, c = check(f.read().splitlines(), spec, a.runs)
        status = "FAIL" if errors else "ok"
        print(f"{status}  {a.platform}  {os.path.basename(path)}  logs={c['logs']} spans={c['spans']} "
              f"screens={c['screens']} journeys={c['journey_started']} errors={len(errors)}")
        for e in errors[:50]:
            print("   ERROR", e)
        if len(errors) > 50:
            print(f"   ... {len(errors) - 50} more")
        bad += bool(errors)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
