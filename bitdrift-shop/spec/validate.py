#!/usr/bin/env python3
"""Validate the bitdrift-shop spec/ for internal consistency.

Usage:  python3 spec/validate.py [--strict]

Checks (errors unless noted):
  * every spec file parses and has `version`
  * unique ids/names (screens, events, spans, fields, flags, personas, crashes,
    per-platform crash impl keys, faults, endpoints)
  * every referenced screen / span / event / field / flag / persona / fault exists
  * platform names are known; probabilities are in [0, 1]; ranges are ordered
  * flag <-> ff_* mirror field consistency
  * every `source:` ref "<root>:<path>:<line>" resolves to an existing file and line
  * every `used_by:` workflow file exists
  * every OPEN-n / D-xxx id referenced in YAML is defined in DECISIONS.md
  * (warning; error with --strict) the cited source line +/-3 contains the expected name

Requires PyYAML (python3 -m pip install pyyaml). Standard library otherwise.
"""
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "spec/validate.py needs PyYAML, which is not installed for %s.\n"
        "Install it with:  python3 -m pip install --user pyyaml\n" % sys.executable
    )
    sys.exit(2)

SPEC_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(SPEC_DIR)
FILES = ["screens", "telemetry", "flags", "personas", "crashes", "faults", "api"]
PLATFORMS = {"android", "ios", "reactnative", "flutter"}
EXTRA_SOURCE_KEYS = {"backend", "kmp"}
PLATFORM_LIST_KEYS = ("platforms", "optional_on", "missing_on", "exposure_optional_on", "persisted_on")
PLATFORM_MAP_KEYS = ("drift", "drift_fields", "drift_level", "drift_values", "source", "source_ui",
                     "impl", "sim_emits", "store_source")
REF_RE = re.compile(r"^([A-Z]+):(.+):(\d+)$")
DECISION_ID_RE = re.compile(r"\b(OPEN-\d+|D-[A-Z]+-[A-Z0-9]+)\b")

errors = []
warnings = []
_file_cache = {}


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def load(name):
    path = os.path.join(SPEC_DIR, name + ".yaml")
    try:
        with open(path) as f:
            data = yaml.safe_load(f)
    except Exception as e:  # noqa: BLE001
        err("%s.yaml: failed to parse: %s" % (name, e))
        return {}
    if not isinstance(data, dict) or "version" not in data:
        err("%s.yaml: missing top-level `version`" % name)
    return data or {}


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def unique(items, key, where):
    seen = set()
    for it in items:
        k = it.get(key) if isinstance(it, dict) else None
        if k is None:
            err("%s: entry without `%s`: %r" % (where, key, it))
            continue
        if k in seen:
            err("%s: duplicate %s %r" % (where, key, k))
        seen.add(k)
    return seen


def read_lines(rel):
    if rel not in _file_cache:
        p = os.path.join(REPO_DIR, rel)
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                _file_cache[rel] = f.read().splitlines()
        except OSError:
            _file_cache[rel] = None
    return _file_cache[rel]


def _token_variants(token):
    """The literal plus the identifier forms tools/codegen emits for it (Kotlin/Swift/TS/Dart)."""
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, os.path.join(here, "..", "tools", "codegen"))
    try:
        import codegen
    except Exception:
        return {token}
    out = {token, token[:1].lower() + token[1:]}  # PascalCase screen names -> camelCase enum cases
    try:
        out.add(codegen.const_name(token))
        out.add(codegen.camel(token).strip("`"))
    except Exception:
        pass
    return out


def check_ref(ref, roots, where, token=None):
    """Resolve '<root>:<path>:<line>'; optionally confirm `token` is near that line."""
    m = REF_RE.match(str(ref))
    if not m:
        err("%s: malformed source ref %r (want ROOT:path:line)" % (where, ref))
        return
    root, path, line = m.group(1), m.group(2), int(m.group(3))
    if root not in roots:
        err("%s: unknown source root %r in %r" % (where, root, ref))
        return
    rel = os.path.normpath(os.path.join(roots[root], path))
    lines = read_lines(rel)
    if lines is None:
        err("%s: source file not found: %s" % (where, rel))
        return
    if line < 1 or line > len(lines):
        err("%s: %s has %d lines, ref points at %d" % (where, rel, len(lines), line))
        return
    if token:
        # Apps migrated to generated constants reference the name as SpecEvents.FOO_BAR /
        # SpecEvents.fooBar / SpecEvents.foo_bar-style identifiers instead of the literal.
        window = "\n".join(lines[max(0, line - 7): line + 6])
        if not any(v in window for v in _token_variants(str(token))):
            warn("%s: %r not found near %s:%d" % (where, token, rel, line))


def check_platforms(entry, where, allow_extra=False):
    if not isinstance(entry, dict):
        return
    ok = PLATFORMS | (EXTRA_SOURCE_KEYS if allow_extra else set())
    for k in PLATFORM_LIST_KEYS:
        for p in as_list(entry.get(k)):
            if p not in PLATFORMS | {"kmp"}:
                err("%s: unknown platform %r in %s" % (where, p, k))
    for k in PLATFORM_MAP_KEYS:
        v = entry.get(k)
        if isinstance(v, dict):
            for p in v:
                if p not in ok | EXTRA_SOURCE_KEYS:
                    err("%s: unknown platform key %r in %s" % (where, p, k))


def check_sources(entry, roots, where, token_for=None):
    """token_for(platform) -> expected token near the cited line (or None).
    An entry may override the expected token per platform with `source_token`."""
    overrides = entry.get("source_token") or {}
    for k in ("source", "source_ui", "store_source", "route_source"):
        v = entry.get(k)
        if v is None:
            continue
        if isinstance(v, dict):
            for p, ref in v.items():
                tok = None
                if k == "source":
                    tok = overrides.get(p) or (token_for(p) if token_for else None)
                check_ref(ref, roots, "%s.%s.%s" % (where, k, p), tok)
        else:
            check_ref(v, roots, "%s.%s" % (where, k))


def check_used_by(entry, where):
    for f in as_list(entry.get("used_by")):
        if not os.path.exists(os.path.join(REPO_DIR, f)):
            err("%s: used_by file not found: %s" % (where, f))


def collect_decision_ids(obj, out):
    if isinstance(obj, dict):
        for v in obj.values():
            collect_decision_ids(v, out)
    elif isinstance(obj, list):
        for v in obj:
            collect_decision_ids(v, out)
    elif isinstance(obj, str):
        out.update(DECISION_ID_RE.findall(obj))


def collect_decision_ids_from_comments(name, out):
    with open(os.path.join(SPEC_DIR, name + ".yaml")) as f:
        for line in f:
            if "#" in line:
                out.update(DECISION_ID_RE.findall(line.split("#", 1)[1]))


def main():
    strict = "--strict" in sys.argv
    spec = {n: load(n) for n in FILES}
    screens_doc, tel, flags_doc, per, crs, flt, api = (spec[n] for n in FILES)

    def roots(doc):
        return doc.get("source_roots", {}) or {}

    # ── screens ───────────────────────────────────────────────────────────
    screens = screens_doc.get("screens", []) or []
    unique(screens, "id", "screens")
    screen_names = unique(screens, "name", "screens")
    unique(screens, "route", "screens")

    # ── telemetry ─────────────────────────────────────────────────────────
    fields = tel.get("fields", []) or []
    field_keys = unique(fields, "key", "telemetry.fields")
    field_by_key = {f["key"]: f for f in fields if isinstance(f, dict) and "key" in f}
    for f in fields:
        check_platforms(f, "telemetry.fields.%s" % f.get("key"))

    events = tel.get("events", []) or []
    event_names = unique(events, "name", "telemetry.events")
    spans = tel.get("spans", []) or []
    span_names = unique(spans, "name", "telemetry.spans")
    gfields = tel.get("global_fields", []) or []
    gfield_keys = unique(gfields, "key", "telemetry.global_fields")
    sdk_events = {e["name"] for e in tel.get("sdk_events", []) or []}
    retired = tel.get("retired_events", []) or []

    def need_fields(keys, where):
        for k in as_list(keys):
            if k not in field_keys:
                err("%s: unknown field %r (add it to telemetry.fields)" % (where, k))

    for e in events:
        w = "telemetry.events.%s" % e.get("name")
        need_fields(e.get("required"), w + ".required")
        need_fields(e.get("optional"), w + ".optional")
        check_platforms(e, w)
        check_used_by(e, w)
        for p, old in (e.get("drift") or {}).items():
            if old in event_names:
                err("%s: drift name %r collides with a spec event" % (w, old))
        drift = e.get("drift") or {}
        check_sources(e, roots(tel), w, lambda p, e=e, d=drift: d.get(p, e["name"]))

    for n in sorted(event_names & sdk_events):
        err("telemetry: %r is both an app event and an sdk_event" % n)
    for r in retired:
        if r.get("name") in event_names:
            err("telemetry.retired_events: %r is also a live spec event" % r.get("name"))
        if r.get("replaced_by") and r["replaced_by"] not in event_names:
            err("telemetry.retired_events.%s: replaced_by %r is not an event" % (r["name"], r["replaced_by"]))
        if r.get("replaced_by_span") and r["replaced_by_span"] not in span_names:
            err("telemetry.retired_events.%s: replaced_by_span %r is not a span" % (r["name"], r["replaced_by_span"]))
        check_platforms(r, "telemetry.retired_events.%s" % r.get("name"))
        check_sources(r, roots(tel), "telemetry.retired_events.%s" % r.get("name"), lambda p, r=r: r["name"])

    span_by_name = {s["name"]: s for s in spans if isinstance(s, dict) and "name" in s}
    for s in spans:
        w = "telemetry.spans.%s" % s.get("name")
        par = s.get("parent")
        if par is not None and par not in span_names:
            err("%s: parent %r is not a span" % (w, par))
        for k in ("fields", "optional_fields", "end_fields"):
            need_fields(s.get(k), "%s.%s" % (w, k))
        check_platforms(s, w)
        check_used_by(s, w)
        check_sources(s, roots(tel), w, lambda p, s=s: s["name"])
    for s in spans:  # cycle check
        seen, cur = set(), s.get("name")
        while cur is not None:
            if cur in seen:
                err("telemetry.spans: parent cycle through %r" % cur)
                break
            seen.add(cur)
            cur = (span_by_name.get(cur) or {}).get("parent")

    flags = flags_doc.get("flags", []) or []
    flag_names = unique(flags, "name", "flags")
    flag_by_name = {f["name"]: f for f in flags if isinstance(f, dict) and "name" in f}

    for g in gfields:
        w = "telemetry.global_fields.%s" % g.get("key")
        if g.get("key") not in field_keys:
            err("%s: key is not in telemetry.fields" % w)
        ff = g.get("from_flag")
        if ff is not None:
            if ff not in flag_names:
                err("%s: from_flag %r is not a flag" % (w, ff))
            elif flag_by_name[ff].get("mirror_field") != g.get("key"):
                err("%s: flag %r mirror_field is %r" % (w, ff, flag_by_name[ff].get("mirror_field")))
        check_platforms(g, w)
        check_sources(g, roots(tel), w, lambda p, g=g: g["key"])

    session = tel.get("session_model") or {}
    check_platforms(session, "telemetry.session_model")
    check_sources(session, roots(tel), "telemetry.session_model")
    md = tel.get("metrics_demo") or {}
    check_platforms(md, "telemetry.metrics_demo")
    check_sources(md, roots(tel), "telemetry.metrics_demo")
    sav = set((field_by_key.get("sim_app_version") or {}).get("values") or [])
    for v in md.get("sim_app_versions") or []:
        if sav and v.get("label") not in sav:
            err("telemetry.metrics_demo: version %r not in sim_app_version values" % v.get("label"))

    # screens -> spans / fields
    pm_values = set((field_by_key.get("payment_method") or {}).get("values") or [])
    for sc in screens:
        w = "screens.%s" % sc.get("id")
        if sc.get("load_span") and sc["load_span"] not in span_names:
            err("%s: load_span %r is not a span" % (w, sc["load_span"]))
        if sc.get("payment_method") and sc["payment_method"] not in pm_values:
            err("%s: payment_method %r not a payment_method value" % (w, sc["payment_method"]))
        for p in (sc.get("platform_routes") or {}):
            if p not in PLATFORMS:
                err("%s: unknown platform %r in platform_routes" % (w, p))
        check_platforms(sc, w)
        drift = sc.get("drift") or {}
        check_sources(sc, roots(screens_doc), w, lambda p, sc=sc, d=drift: d.get(p, sc["name"]))

    # ── personas ──────────────────────────────────────────────────────────
    personas = per.get("personas", []) or []
    persona_ids = unique(personas, "id", "personas")
    unique(personas, "label", "personas")
    var_values = set((field_by_key.get("variant") or {}).get("values") or [])
    for p in personas:
        if var_values and p.get("label") not in var_values:
            err("personas.%s: label %r not in telemetry field `variant` values" % (p.get("id"), p.get("label")))
    check_sources(per, roots(per), "personas")
    for name, block in (per.get("probabilities") or {}).items():
        w = "personas.probabilities.%s" % name
        check_platforms(block, w)
        check_sources(block, roots(per), w)
        for pid in persona_ids:
            if pid not in block:
                err("%s: missing persona %r" % (w, pid))
                continue
            v = block[pid]
            if isinstance(v, dict):
                if any((not isinstance(x, (int, float))) or x < 0 for x in v.values()) or sum(v.values()) <= 0:
                    err("%s.%s: weights must be non-negative with positive sum" % (w, pid))
                if name == "payment_weights":
                    for m in v:
                        if m not in pm_values:
                            err("%s.%s: %r is not a payment_method value" % (w, pid, m))
            elif isinstance(v, list):
                if len(v) != 2 or v[0] > v[1]:
                    err("%s.%s: range must be [min, max]" % (w, pid))
            elif not isinstance(v, (int, float)) or not 0 <= v <= 1:
                err("%s.%s: probability %r outside [0,1]" % (w, pid, v))
        for k in block:
            if k not in persona_ids and k not in ("source",):
                err("%s: unknown persona key %r" % (w, k))
    jc = per.get("journey_constants") or {}
    if not 0 <= jc.get("payment_retry", 0) <= 1:
        err("personas.journey_constants.payment_retry outside [0,1]")
    for m in jc.get("retry_methods") or []:
        if m not in pm_values:
            err("personas.journey_constants.retry_methods: %r not a payment_method value" % m)
    check_sources(jc, roots(per), "personas.journey_constants")
    sd = per.get("sim_data") or {}
    for k in ("search_terms", "entities"):
        blk = sd.get(k) or {}
        vals = blk.get("values") or []
        if not vals or len(vals) != len(set(vals)):
            err("personas.sim_data.%s: values empty or not unique" % k)
        check_platforms(blk, "personas.sim_data.%s" % k)
        check_sources(blk, roots(per), "personas.sim_data.%s" % k)
    if sd.get("fallback_source"):
        check_sources({"source": sd["fallback_source"]}, roots(per), "personas.sim_data.fallback")

    # ── flags ─────────────────────────────────────────────────────────────
    fault_ids = {f.get("id") for f in (flt.get("faults") or [])}
    for f in flags:
        w = "flags.%s" % f.get("name")
        mf = f.get("mirror_field")
        if mf != "ff_" + str(f.get("name")):
            err("%s: mirror_field should be ff_%s" % (w, f.get("name")))
        if mf not in gfield_keys:
            err("%s: mirror_field %r not listed in telemetry.global_fields" % (w, mf))
        kind = f.get("kind")
        vals = f.get("values")
        if kind == "persona":
            if not isinstance(vals, dict) or set(vals) != persona_ids:
                err("%s: persona flag must define a value for exactly %s" % (w, sorted(persona_ids)))
        elif kind == "toggle":
            if f.get("toggle") not in fault_ids:
                err("%s: toggle %r is not a faults.yaml id" % (w, f.get("toggle")))
            if not isinstance(vals, dict) or set(vals) != {"on", "off"}:
                err("%s: toggle flag values must be {on, off}" % w)
        elif kind == "persistent":
            if not isinstance(vals, list) or len(vals) < 2:
                err("%s: persistent flag needs a list of >= 2 values" % w)
        else:
            err("%s: unknown kind %r" % (w, kind))
        check_platforms(f, w)
        check_used_by(f, w)
        check_sources(f, roots(flags_doc), w, lambda p, f=f: f["name"])
    persistent = [f for f in flags if f.get("kind") == "persistent"]
    if len(persistent) > 3:
        err("flags: more than 3 persistent flags (hard cap, A:PersistentFeatureFlags.kt:30)")
    for g in gfields:
        if g["key"].startswith("ff_") and g["key"] != "ff_variant" and not g.get("from_flag"):
            err("telemetry.global_fields.%s: ff_* field without from_flag" % g["key"])

    # ── crashes ───────────────────────────────────────────────────────────
    crashes = crs.get("crashes", []) or []
    unique(crashes, "id", "crashes")
    impl_seen = {p: set() for p in PLATFORMS}
    vendor_ids = {v.get("id") for v in (api.get("vendor_sdks") or [])}
    cats = {"runtime_exception", "background_thread", "lock_contention", "vendor_sdk", "native_signal",
            "memory_fault", "oom", "watchdog_hang", "process_exit"}
    issue_types = {"crash", "native_crash", "oom_termination", "app_hang", "none"}
    for c in crashes:
        w = "crashes.%s" % c.get("id")
        impl = c.get("impl") or {}
        if not impl:
            err("%s: no impl" % w)
        for p, key in impl.items():
            if p not in PLATFORMS:
                err("%s: unknown platform %r in impl" % (w, p))
                continue
            if key in impl_seen[p]:
                err("%s: duplicate %s impl key %r" % (w, p, key))
            impl_seen[p].add(key)
        if c.get("category") not in cats:
            err("%s: unknown category %r" % (w, c.get("category")))
        ei = c.get("expected_issue")
        for t in (ei.values() if isinstance(ei, dict) else [ei]):
            if t not in issue_types:
                err("%s: unknown expected_issue %r" % (w, t))
        if c.get("vendor") and c["vendor"] not in vendor_ids:
            err("%s: vendor %r not in api.yaml vendor_sdks" % (w, c["vendor"]))
        for p in as_list(c.get("missing_on")):
            if p in impl:
                err("%s: %s is both implemented and missing_on" % (w, p))
        if set((c.get("source") or {})) != set(impl):
            err("%s: source platforms %s != impl platforms %s" % (w, sorted(c.get("source") or {}), sorted(impl)))
        check_platforms(c, w)
        check_sources(c, roots(crs), w, lambda p, impl=impl: impl.get(p))
    for p, src in (crs.get("sweep") or {}).items():
        if isinstance(src, dict) and src.get("source"):
            check_ref(src["source"], roots(crs), "crashes.sweep.%s" % p)
    for p, t in (crs.get("timings") or {}).items():
        check_ref(t.get("source"), roots(crs), "crashes.timings.%s" % p)

    # ── faults ────────────────────────────────────────────────────────────
    faults = flt.get("faults", []) or []
    unique(faults, "id", "faults")
    for f in faults:
        w = "faults.%s" % f.get("id")
        if f.get("target_screen") and f["target_screen"] not in screen_names:
            err("%s: target_screen %r is not a screen name" % (w, f["target_screen"]))
        for k in ("log_event", "resume_event"):
            if f.get(k) and f[k] not in event_names:
                err("%s: %s %r is not an event" % (w, k, f[k]))
        if f.get("flag") and f["flag"] not in flag_names:
            err("%s: flag %r is not a flag" % (w, f["flag"]))
        if f.get("field") and f["field"] not in field_keys:
            err("%s: field %r is not a field" % (w, f["field"]))
        if f.get("requires") and f["requires"] not in fault_ids:
            err("%s: requires %r is not a fault" % (w, f["requires"]))
        el = f.get("eligible_when") or {}
        if el.get("persona") and el["persona"] not in persona_ids:
            err("%s: eligible_when.persona %r unknown" % (w, el["persona"]))
        if f.get("probability") is not None and not 0 <= f["probability"] <= 1:
            err("%s: probability outside [0,1]" % w)
        for p in (f.get("store") or {}):
            if p not in PLATFORMS:
                err("%s: unknown platform %r in store" % (w, p))
        check_platforms(f, w)
        check_sources(f, roots(flt), w)
    st = flt.get("startup") or {}
    check_sources(st, roots(flt), "faults.startup")
    for o in flt.get("other_persisted") or []:
        check_sources(o, roots(flt), "faults.other_persisted")

    # ── api ───────────────────────────────────────────────────────────────
    eps = api.get("endpoints", []) or []
    unique(eps, "id", "api.endpoints")
    seen_mp = set()
    for e in eps:
        w = "api.endpoints.%s" % e.get("id")
        mp = (e.get("method"), e.get("path"))
        if mp in seen_mp:
            err("%s: duplicate method+path %s" % (w, mp))
        seen_mp.add(mp)
        if e.get("method") not in ("GET", "POST", "DELETE", "PUT"):
            err("%s: bad method %r" % (w, e.get("method")))
        if not str(e.get("path", "")).startswith("/api/"):
            err("%s: path must start with /api/" % w)
        tpl = e.get("path_template")
        if tpl:
            if re.sub(r"<[^>]+>", "X", tpl) != re.sub(r"\{[^}]+\}", "X", e["path"]):
                err("%s: path_template %r does not match path %r" % (w, tpl, e["path"]))
        if e.get("payment_method") and e["payment_method"] not in pm_values:
            err("%s: payment_method %r unknown" % (w, e["payment_method"]))
        check_platforms(e, w, allow_extra=True)
        check_sources(e, roots(api), w)
    for v in api.get("vendor_sdks") or []:
        if not str(v.get("url", "")).startswith("https://"):
            err("api.vendor_sdks.%s: url must be https" % v.get("id"))
        check_sources(v, roots(api), "api.vendor_sdks.%s" % v.get("id"), lambda p, v=v: v["url"])
    check_sources(api.get("backend") or {}, roots(api), "api.backend")
    check_sources(api.get("sdk_release_check") or {}, roots(api), "api.sdk_release_check")

    # ── decision ids ──────────────────────────────────────────────────────
    ids = set()
    for n in FILES:
        collect_decision_ids(spec[n], ids)
        collect_decision_ids_from_comments(n, ids)
    dec_path = os.path.join(SPEC_DIR, "DECISIONS.md")
    if not os.path.exists(dec_path):
        err("spec/DECISIONS.md is missing")
    else:
        with open(dec_path) as f:
            text = f.read()
        defined = set(re.findall(r"^#+\s*(OPEN-\d+|D-[A-Z]+-[A-Z0-9]+)\b", text, re.M))
        for i in sorted(ids - defined):
            err("decision id %s is referenced in spec YAML but has no heading in DECISIONS.md" % i)

    # ── report ────────────────────────────────────────────────────────────
    counts = (
        "screens=%d events=%d spans=%d fields=%d global_fields=%d flags=%d personas=%d "
        "crashes=%d faults=%d endpoints=%d"
        % (len(screens), len(events), len(spans), len(fields), len(gfields), len(flags),
           len(personas), len(crashes), len(faults), len(eps))
    )
    for w in warnings:
        print("WARN  " + w)
    for e in errors:
        print("ERROR " + e)
    print(counts)
    if errors or (strict and warnings):
        print("FAILED: %d error(s), %d warning(s)" % (len(errors), len(warnings)))
        return 1
    print("OK: %d warning(s)" % len(warnings))
    return 0


if __name__ == "__main__":
    sys.exit(main())
