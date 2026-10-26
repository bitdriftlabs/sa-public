"""Reference journey interpreter (Python). The app interpreters are line-for-line ports:
android JourneyEngine.kt, ios JourneyEngine.swift, reactnative src/sim/journeyEngine.ts,
flutter lib/sim/journey_engine.dart. tools/journey/golden.py runs this against a fake
adapter to produce golden.json, which each app's unit tests replay.
"""
import re

M32 = 0xFFFFFFFF
TEMPLATE = re.compile(r"\{([A-Za-z0-9_.]+)\}")


def journey_seed(sim_seed, run):
    return (sim_seed * 1000003 + run) & M32


def imul(a, b):
    return (a * b) & M32


class Rng:
    """mulberry32: next() in [0, 1)."""

    def __init__(self, seed):
        self.s = seed & M32

    def next(self):
        self.s = (self.s + 0x6D2B79F5) & M32
        t = self.s
        t = imul(t ^ (t >> 15), t | 1)
        t = ((t + imul(t ^ (t >> 7), t | 61)) & M32) ^ t
        return ((t ^ (t >> 14)) & M32) / 4294967296.0


class Stop(Exception):
    def __init__(self, outcome):
        self.outcome = outcome


class JourneyEngine:
    """One engine per simulator; fault counters persist across journeys."""

    def __init__(self, bundle, adapter):
        self.b = bundle
        self.a = adapter
        self.eligible = {}

    def run(self, persona, run, sim_seed, toggles, infinite):
        self.persona = persona
        self.toggles = set(toggles)
        self.infinite = infinite
        self.rng = Rng(journey_seed(sim_seed, run))
        self.vars = dict(self.b["personas"][persona]["vars"])
        self.vars.update({"run": str(run), "sim_seed": str(sim_seed), "persona": persona})
        self.spans = {}
        self.crash_fired = False
        try:
            self.block(self.b["journey"])
        except Stop as s:
            return s.outcome
        return "completed"

    # ── helpers ──────────────────────────────────────────────────────────────
    def t(self, s):
        def sub(m):
            v = self.vars.get(m.group(1), "")
            return str(len(v)) if isinstance(v, list) else v
        return TEMPLATE.sub(sub, s)

    def tm(self, m):
        return {k: self.t(v) for k, v in m.items()}

    def lst(self, name):
        v = self.vars.get(name)
        if not isinstance(v, list):
            v = []
            self.vars[name] = v
        return v

    def p(self, chance):
        table = chance["default"]
        by = chance.get("by")
        if by is not None:
            table = chance["cases"].get(self.vars.get(by, ""), table)
        return table[self.persona]

    def cond_ok(self, op):
        """Draws for `chance` first (always), then checks every other condition."""
        ok = True
        if "chance" in op:
            ok = self.rng.next() < self.p(op["chance"])
        if "toggle" in op and op["toggle"] not in self.toggles:
            ok = False
        if "not_toggle" in op and op["not_toggle"] in self.toggles:
            ok = False
        if "eq" in op and self.vars.get(op["eq"][0], "") != op["eq"][1]:
            ok = False
        if "min_len" in op and len(self.lst(op["min_len"][0])) < op["min_len"][1]:
            ok = False
        return ok

    # ── interpreter ──────────────────────────────────────────────────────────
    def block(self, ops):
        for op in ops:
            if self.a.is_cancelled():
                raise Stop("cancelled")
            self.step(op)

    def step(self, op):
        k = op["op"]
        a = self.a
        if k == "new_session":
            a.start_new_session()
        elif k == "exposures":
            a.apply_exposures(self.persona)
        elif k == "entity":
            ents = self.b["entities"]
            self.vars["entity"] = ents[(int(self.vars["run"]) - 1) % len(ents)]
            a.set_entity(self.vars["entity"])
        elif k == "wait":
            a.delay(op["ms"])
        elif k == "nav":
            a.navigate(op["screen"], self.tm(op["args"]))
            a.delay(self.b["step_delay_ms"])
        elif k == "api":
            res = a.call_api(op["endpoint"], self.tm(op["args"]))
            for s in op["save"]:
                v = res.get(s["key"]) if isinstance(res, dict) else None
                if "item" in s:
                    items = [str(x[s["item"]]) for x in v if isinstance(x, dict) and s["item"] in x] if isinstance(v, list) else []
                    self.vars[s["var"]] = items if items else list(s["default"])
                else:
                    self.vars[s["var"]] = str(v) if v not in (None, "") else self.t(s["default"])
        elif k == "log":
            a.log(op["level"], op["event"], self.tm(op["fields"]))
        elif k == "span_start":
            self.start_span(op)
        elif k == "span_end":
            h = self.spans.pop(op["span"], None)
            if h is not None:
                a.end_span(h, op["result"], self.tm(op["fields"]))
        elif k == "span":
            # Scoped span: success when the block finishes or the journey stops inside it
            # (fault / crash / outcome); canceled when the run is cancelled.
            self.start_span(op)
            result = "canceled"
            try:
                self.block(op["do"])
                result = "success"
            except Stop as s:
                result = "canceled" if s.outcome == "cancelled" else "success"
                raise
            finally:
                h = self.spans.pop(op["span"], None)
                if h is not None:
                    a.end_span(h, result, {})
        elif k == "set":
            for key, v in op["values"].items():
                self.vars[key] = self.t(v)
        elif k == "pick":
            items = list(op["values"]) if "values" in op else list(self.lst(op["from"]))
            if "exclude" in op:
                ex = self.t(op["exclude"])
                items = [x for x in items if x != ex]
            r = self.rng.next()
            self.vars[op["into"]] = items[int(r * len(items))] if items else ""
        elif k == "rand_int":
            self.vars[op["into"]] = str(op["min"] + int(self.rng.next() * (op["max"] - op["min"] + 1)))
        elif k == "choose":
            weights = op["weights"][self.persona]
            total = 0.0
            for _, w in weights:
                total += w
            x = self.rng.next() * total
            pick, acc = weights[-1][0], 0.0
            for key, w in weights:
                acc += w
                if x < acc:
                    pick = key
                    break
            if op.get("into"):
                self.vars[op["into"]] = pick
            self.block(op["branches"].get(pick, []))
        elif k == "if":
            self.block(op["then"] if self.cond_ok(op) else op["else"])
        elif k == "switch":
            self.block(op["cases"].get(self.vars.get(op["var"], ""), op["default"]))
        elif k == "repeat":
            lo, hi = op["ranges"][self.persona]
            n = lo + int(self.rng.next() * (hi - lo + 1))
            for _ in range(n):
                self.block(op["do"])
        elif k == "for_each":
            for item in list(self.lst(op["list"])):
                self.vars[op["as"]] = item
                self.block(op["do"])
        elif k == "list_add":
            self.lst(op["list"]).append(self.t(op["value"]))
        elif k == "list_remove_random":
            items = self.lst(op["list"])
            r = self.rng.next()
            self.vars[op["into"]] = items.pop(int(r * len(items))) if items else ""
        elif k == "list_clear":
            self.lst(op["list"]).clear()
        elif k == "last":
            items = self.lst(op["list"])
            self.vars[op["into"]] = items[-1] if items else self.t(op["default"])
        elif k == "fault":
            self.fault(op)
        elif k == "crash_point":
            if "crash_loop" in self.toggles and not self.crash_fired and \
                    op["point"] in (self.vars.get("crash_point"), "confirmation"):
                self.crash_fired = True
                a.add_field("crash_journey_point", op["point"])
                a.fire_crash()
                raise Stop("crash")
        elif k == "stop":
            raise Stop(op["outcome"])
        else:
            raise ValueError(f"unknown op {k}")

    def start_span(self, op):
        parent = self.spans.get(op["parent"]) if op["parent"] else None
        self.spans[op["span"]] = self.a.start_span(op["span"], parent, self.tm(op["fields"]))

    def fault(self, op):
        fid = op["fault"]
        if fid not in self.toggles:
            return
        self.eligible[fid] = self.eligible.get(fid, 0) + 1
        random_hit = self.rng.next() < op["probability"]
        forced = self.infinite and self.eligible[fid] >= op["force_after"]
        if not random_hit and not forced:
            return
        self.eligible[fid] = 0
        self.vars["trigger_mode"] = "random" if random_hit else "forced_infinite"
        self.a.log(op["level"], op["event"], self.tm(op["fields"]))
        self.a.inject_fault(fid)
        raise Stop("fault")


# ── Trace adapter (golden files and unit tests) ─────────────────────────────

def fmt_fields(m):
    return "{" + ", ".join(f"{k}={m[k]}" for k in sorted(m)) + "}"


class TraceAdapter:
    """Records every adapter call as one canonical line (see tools/journey/README.md)."""

    def __init__(self, fixture):
        self.fixture = fixture
        self.lines = []

    def is_cancelled(self):
        return False

    def start_new_session(self):
        self.lines.append("new_session")

    def apply_exposures(self, persona):
        self.lines.append(f"exposures {persona}")

    def set_entity(self, entity):
        self.lines.append(f"entity {entity}")

    def delay(self, ms):
        self.lines.append(f"wait {ms}")

    def navigate(self, screen, args):
        self.lines.append(f"nav {screen} {fmt_fields(args)}")

    def call_api(self, endpoint, args):
        self.lines.append(f"api {endpoint} {fmt_fields(args)}")
        if endpoint in (self.fixture.get("fail") or []):
            return None
        return self.fixture.get(endpoint, {})

    def log(self, level, event, fields):
        self.lines.append(f"log {level} {event} {fmt_fields(fields)}")

    def start_span(self, name, parent, fields):
        self.lines.append(f"span_start {name} {parent or '-'} {fmt_fields(fields)}")
        return name

    def end_span(self, handle, result, fields):
        self.lines.append(f"span_end {handle} {result} {fmt_fields(fields)}")

    def add_field(self, key, value):
        self.lines.append(f"field {key}={value}")

    def inject_fault(self, fid):
        self.lines.append(f"fault {fid}")

    def fire_crash(self):
        self.lines.append("crash")
