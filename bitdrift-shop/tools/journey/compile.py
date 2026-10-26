#!/usr/bin/env python3
"""Compile spec/journey.yaml into the normalized journey bundle every app interprets.

Resolves every reference (personas.yaml decisions and constants, faults.yaml, flags.yaml,
screens, events, spans, endpoints), inlines procedures, and validates the graph. The
bundle's op shapes are documented in tools/journey/README.md.

    compile.py            print the bundle (JSON) to stdout, or exit 1 listing errors
"""
import json
import os
import re
import sys

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEMPLATE = re.compile(r"\{([A-Za-z0-9_.]+)\}")
TOGGLES = {"crash_loop", "anr", "force_quit"}
BUILTIN_VARS = {"run", "sim_seed", "persona", "variant", "entity", "crash_point", "trigger_mode"}
RESULTS = {"success", "failure", "canceled"}


def load(name):
    with open(os.path.join(ROOT, "spec", name + ".yaml")) as f:
        return yaml.safe_load(f)


class Compiler:
    def __init__(self):
        self.j = load("journey")
        self.per = load("personas")
        self.faults = {f["id"]: f for f in load("faults")["faults"]}
        self.flags = load("flags")["flags"]
        tel = load("telemetry")
        self.events = {e["name"]: e for e in tel["events"]}
        self.spans = {s["name"]: s for s in tel["spans"]}
        self.fields = {f["key"] for f in tel["fields"]} | {g["key"] for g in tel.get("global_fields", [])}
        self.screens = {s["id"]: s for s in load("screens")["screens"]}
        self.endpoints = {e["id"]: e for e in load("api")["endpoints"]}
        self.persona_ids = [p["id"] for p in self.per["personas"]]
        self.probs = self.per["probabilities"]
        self.consts = self.per["journey_constants"]
        self.sim_data = self.per["sim_data"]
        self.errors = []
        self.assigned = set(BUILTIN_VARS) | {"flag." + f["name"] for f in self.flags if f["kind"] == "persona"}
        self.used = []  # (var, where)
        self.spans_used = set()
        self.events_used = set()

    def err(self, where, msg):
        self.errors.append(f"{where}: {msg}")

    # ── value helpers ────────────────────────────────────────────────────────
    def tmpl(self, value, where):
        if not isinstance(value, str):
            value = str(value).lower() if isinstance(value, bool) else str(value)
        for name in TEMPLATE.findall(value):
            self.used.append((name, where))
        return value

    def tmpl_map(self, m, where):
        return {str(k): self.tmpl(v, where) for k, v in (m or {}).items()}

    def per_persona(self, decision, where, shape):
        p = self.probs.get(decision)
        if p is None:
            self.err(where, f"unknown personas.yaml decision '{decision}'")
            return {}
        out = {}
        for pid in self.persona_ids:
            v = p.get(pid)
            if shape == "prob" and not isinstance(v, (int, float)):
                self.err(where, f"decision '{decision}' is not a probability for {pid}")
            if shape == "weights" and not isinstance(v, dict):
                self.err(where, f"decision '{decision}' is not a weights map for {pid}")
            if shape == "range" and not (isinstance(v, list) and len(v) == 2):
                self.err(where, f"decision '{decision}' is not a [min, max] range for {pid}")
            if shape == "weights" and isinstance(v, dict):
                v = [[k, float(w)] for k, w in v.items()]
            elif shape == "prob":
                v = float(v) if isinstance(v, (int, float)) else 0.0
            out[pid] = v
        return out

    def chance(self, c, where):
        """A probability decision name, a constant name, or {by, cases, default}."""
        def one(name):
            if name in self.probs:
                return self.per_persona(name, where, "prob")
            if name in self.consts and isinstance(self.consts[name], (int, float)):
                return {pid: float(self.consts[name]) for pid in self.persona_ids}
            self.err(where, f"unknown probability '{name}'")
            return {}
        if isinstance(c, str):
            return {"default": one(c)}
        out = {"by": c["by"], "default": one(c["default"]), "cases": {str(k): one(v) for k, v in c["cases"].items()}}
        self.used.append((c["by"], where))
        return out

    def ms(self, v, where):
        if isinstance(v, int):
            return v
        if v in self.consts and isinstance(self.consts[v], int):
            return self.consts[v]
        self.err(where, f"wait: '{v}' is not a number or an integer journey_constants name")
        return 0

    def list_source(self, name, where):
        """pick/from: a sim_data list or constant list is inlined; otherwise a list variable."""
        if name == "crash_points":
            return {"values": list(self.j["crash_points"])}
        sd = self.sim_data.get(name)
        if isinstance(sd, dict) and isinstance(sd.get("values"), list):
            return {"values": [str(x) for x in sd["values"]]}
        if isinstance(self.consts.get(name), list):
            return {"values": [str(x) for x in self.consts[name]]}
        self.used.append((name, where))
        return {"from": name}

    def default_value(self, d, where):
        if isinstance(d, str) and d in self.sim_data and not isinstance(self.sim_data[d], dict):
            return str(self.sim_data[d])
        return self.tmpl(d, where) if isinstance(d, str) else d

    # ── ops ──────────────────────────────────────────────────────────────────
    def block(self, steps, where):
        out = []
        for i, step in enumerate(steps or []):
            out.extend(self.op(step, f"{where}[{i}]"))
        return out

    def op(self, step, where):
        if isinstance(step, str):
            name, arg, rest = step, None, {}
        elif isinstance(step, dict) and step:
            name = next(iter(step))
            arg, rest = step[name], {k: v for k, v in step.items() if k != name}
        else:
            self.err(where, f"bad step {step!r}")
            return []
        where = f"{where} {name}"
        fn = getattr(self, "op_" + name, None)
        if fn is None:
            self.err(where, f"unknown op '{name}'")
            return []
        res = fn(arg, rest, where)
        return res if isinstance(res, list) else [res]

    def op_new_session(self, a, r, w):
        return {"op": "new_session"}

    def op_exposures(self, a, r, w):
        return {"op": "exposures"}

    def op_entity(self, a, r, w):
        return {"op": "entity"}

    def op_wait(self, a, r, w):
        return {"op": "wait", "ms": self.ms(a, w)}

    def op_nav(self, a, r, w):
        s = self.screens.get(a)
        if s is None:
            self.err(w, f"unknown screen '{a}'")
            return []
        params = set(re.findall(r"\{(\w+)\}", s["route"]))
        args = self.tmpl_map(r.get("args"), w)
        if set(args) != params:
            self.err(w, f"args {sorted(args)} != route params {sorted(params)} of '{s['route']}'")
        return {"op": "nav", "screen": a, "args": args}

    def op_api(self, a, r, w):
        if a not in self.endpoints:
            self.err(w, f"unknown endpoint '{a}'")
        save = []
        for var, spec in (r.get("save") or {}).items():
            path = spec["path"]
            m = re.fullmatch(r"(\w+)\[\]\.(\w+)", path)
            d = self.default_value(spec.get("default", ""), w)
            if m:
                save.append({"var": var, "key": m.group(1), "item": m.group(2), "default": [d] if d != "" else []})
            elif re.fullmatch(r"\w+", path):
                save.append({"var": var, "key": path, "default": d})
            else:
                self.err(w, f"bad save path '{path}'")
            self.assigned.add(var)
        return {"op": "api", "endpoint": a, "args": self.tmpl_map(r.get("args"), w), "save": save}

    def event_fields(self, event, fields, w):
        ev = self.events.get(event)
        if ev is None:
            self.err(w, f"unknown event '{event}'")
            return None
        self.events_used.add(event)
        for k in fields:
            if k not in self.fields:
                self.err(w, f"field '{k}' is not in the telemetry.yaml registry")
        for req in ev.get("required") or []:
            if req not in fields:
                self.err(w, f"event '{event}' requires field '{req}'")
        level = ev.get("level")
        if not isinstance(level, str):
            self.err(w, f"event '{event}' has no single level")
        return level

    def op_log(self, a, r, w):
        fields = self.tmpl_map(r.get("fields"), w)
        level = self.event_fields(a, fields, w)
        return {"op": "log", "level": level, "event": a, "fields": fields}

    def span_check(self, span, parent, w):
        sp = self.spans.get(span)
        if sp is None:
            self.err(w, f"unknown span '{span}'")
            return
        self.spans_used.add(span)
        if sp.get("parent") != parent:
            self.err(w, f"span '{span}' parent is '{parent}', telemetry.yaml says '{sp.get('parent')}'")

    def op_span_start(self, a, r, w):
        self.span_check(a, r.get("parent"), w)
        return {"op": "span_start", "span": a, "parent": r.get("parent"), "fields": self.tmpl_map(r.get("fields"), w)}

    def op_span_end(self, a, r, w):
        if r.get("result") not in RESULTS:
            self.err(w, f"result must be one of {sorted(RESULTS)}")
        return {"op": "span_end", "span": a, "result": r.get("result"), "fields": self.tmpl_map(r.get("fields"), w)}

    def op_span(self, a, r, w):
        self.span_check(a, r.get("parent"), w)
        return {"op": "span", "span": a, "parent": r.get("parent"), "fields": self.tmpl_map(r.get("fields"), w),
                "do": self.block(r.get("do"), w)}

    def op_set(self, a, r, w):
        for k in a:
            self.assigned.add(k)
        return {"op": "set", "values": self.tmpl_map(a, w)}

    def op_pick(self, a, r, w):
        self.assigned.add(a)
        out = {"op": "pick", "into": a}
        out.update(self.list_source(r["from"], w))
        if "exclude" in r:
            out["exclude"] = self.tmpl(r["exclude"], w)
        return out

    def op_rand_int(self, a, r, w):
        self.assigned.add(a)
        rng = r["range"]
        if isinstance(rng, str):
            rng = self.consts.get(rng)
        if not (isinstance(rng, list) and len(rng) == 2 and rng[0] <= rng[1]):
            self.err(w, f"range must be a [min, max] constant or literal")
            rng = [0, 0]
        return {"op": "rand_int", "into": a, "min": int(rng[0]), "max": int(rng[1])}

    def op_choose(self, a, r, w):
        weights = self.per_persona(a, w, "weights")
        into = r.get("into")
        if into:
            self.assigned.add(into)
        keys = {k for v in weights.values() for k, _ in v}
        branches = {}
        for k, steps in (r.get("branches") or {}).items():
            if k not in keys:
                self.err(w, f"branch '{k}' is not a key of '{a}'")
            branches[k] = self.block(steps, f"{w}.{k}")
        return {"op": "choose", "into": into, "weights": weights, "branches": branches}

    def cond(self, c, w):
        out = {}
        for k, v in c.items():
            if k == "chance":
                out["chance"] = self.chance(v, w)
            elif k in ("toggle", "not_toggle"):
                if v not in TOGGLES:
                    self.err(w, f"unknown toggle '{v}' (one of {sorted(TOGGLES)})")
                out[k] = v
            elif k == "eq":
                self.used.append((v[0], w))
                out["eq"] = [v[0], str(v[1])]
            elif k == "min_len":
                self.used.append((v[0], w))
                out["min_len"] = [v[0], int(v[1])]
            else:
                self.err(w, f"unknown condition '{k}'")
        return out

    def op_if(self, a, r, w):
        out = {"op": "if"}
        out.update(self.cond(a, w))
        out["then"] = self.block(r.get("then"), w + ".then")
        out["else"] = self.block(r.get("else"), w + ".else")
        return out

    def op_switch(self, a, r, w):
        self.used.append((a, w))
        return {"op": "switch", "var": a,
                "cases": {str(k): self.block(v, f"{w}.{k}") for k, v in (r.get("cases") or {}).items()},
                "default": self.block(r.get("default"), w + ".default")}

    def op_repeat(self, a, r, w):
        return {"op": "repeat", "ranges": self.per_persona(a, w, "range"), "do": self.block(r.get("do"), w)}

    def op_for_each(self, a, r, w):
        self.used.append((a, w))
        self.assigned.add(r["as"])
        return {"op": "for_each", "list": a, "as": r["as"], "do": self.block(r.get("do"), w)}

    def op_list_add(self, a, r, w):
        self.assigned.add(a)
        return {"op": "list_add", "list": a, "value": self.tmpl(r["value"], w)}

    def op_list_remove_random(self, a, r, w):
        self.used.append((a, w))
        self.assigned.add(r["into"])
        return {"op": "list_remove_random", "list": a, "into": r["into"]}

    def op_list_clear(self, a, r, w):
        return {"op": "list_clear", "list": a}

    def op_last(self, a, r, w):
        self.used.append((a, w))
        self.assigned.add(r["into"])
        return {"op": "last", "list": a, "into": r["into"], "default": self.tmpl(r.get("default", ""), w)}

    def op_call(self, a, r, w):
        procs = self.j.get("procedures") or {}
        if a not in procs:
            self.err(w, f"unknown procedure '{a}'")
            return []
        return self.block(procs[a], f"{w}({a})")

    def op_fault(self, a, r, w):
        f = self.faults.get(a)
        if f is None or a not in TOGGLES:
            self.err(w, f"fault '{a}' must be a faults.yaml id with a toggle ({sorted(TOGGLES)})")
            return []
        fields = self.tmpl_map(r.get("fields"), w)
        if r.get("log") != f.get("log_event"):
            self.err(w, f"log '{r.get('log')}' != faults.yaml log_event '{f.get('log_event')}'")
        level = self.event_fields(r.get("log"), fields, w)
        return {"op": "fault", "fault": a, "probability": float(f["probability"]),
                "force_after": int(f["force_after_eligible_journeys"]), "level": level, "event": r.get("log"), "fields": fields}

    def op_crash_point(self, a, r, w):
        if a not in self.j["crash_points"]:
            self.err(w, f"'{a}' is not in crash_points")
        return {"op": "crash_point", "point": a}

    def op_stop(self, a, r, w):
        return {"op": "stop", "outcome": a}

    # ── bundle ───────────────────────────────────────────────────────────────
    def compile(self):
        journey = self.block(self.j["journey"], "journey")
        for name, where in self.used:
            if name not in self.assigned:
                self.err(where, f"variable '{name}' is never assigned")
        if "confirmation" not in self.j["crash_points"]:
            self.err("crash_points", "must include 'confirmation' (the fallback point)")
        for fld in self.j.get("volatile_fields") or []:
            if fld not in self.fields:
                self.err("volatile_fields", f"'{fld}' is not a telemetry field")
        personas = {}
        for p in self.per["personas"]:
            vars_ = {"variant": p["label"]}
            for f in self.flags:
                if f["kind"] == "persona":
                    vars_["flag." + f["name"]] = f["values"][p["id"]]
            personas[p["id"]] = {"vars": vars_}
        bundle = {
            "version": self.j["version"],
            "step_delay_ms": self.consts["step_delay_ms"],
            "entities": [str(e) for e in self.sim_data["entities"]["values"]],
            "personas": personas,
            "journey": journey,
        }
        return bundle

    def diff_info(self):
        """What tools/conformance --diff compares: the journey's own events and spans."""
        return {
            "volatile_fields": list(self.j.get("volatile_fields") or []),
            "events": sorted(self.events_used),
            "spans": sorted(self.spans_used),
        }


def compile_bundle():
    c = Compiler()
    bundle = c.compile()
    if c.errors:
        raise SystemExit("spec/journey.yaml has errors:\n  " + "\n  ".join(c.errors))
    return bundle, c.diff_info()


def bundle_json(bundle):
    s = json.dumps(bundle, separators=(",", ":"), ensure_ascii=True)
    for bad in ("$", '"""', "'''", '"#'):
        if bad in s:
            raise SystemExit(f"journey bundle contains {bad!r}, which breaks the embedded raw string")
    return s


def test_fixture():
    return load("journey")["test_fixture"]


if __name__ == "__main__":
    b, _ = compile_bundle()
    json.dump(b, sys.stdout, indent=1)
    print()
