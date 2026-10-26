# spec/: single source of truth for bitdrift-shop

These files hold the shared *data* behind the four supported apps (android, ios,
reactnative, flutter): names, values, probabilities, timings and the crash catalog. The
values were extracted from the code as it stands, with Android as the reference. Every
cross-platform mismatch and how it was resolved is recorded in **[DECISIONS.md](DECISIONS.md)**,
including the open questions in "Needs user decision".

Later phases generate per-language constants from these files (Phase 2b), validate
recorded event streams against them (Phase 3), and add `journey.yaml`, `workflows/` and
`dashboards/` (Phases 4-5).

| File | What it holds |
|---|---|
| `screens.yaml` | The 19 screens: id, `_screen_name` value, Android/iOS route template, funnel step, screen-load span, RN/Flutter route keys |
| `telemetry.yaml` | Field-key registry, global fields, every app-emitted event (level, trigger, required/optional fields), the span tree, SDK-owned names that workflows reference, retired names, metrics-demo waveforms |
| `flags.yaml` | Feature flags: persona-driven, toggle-driven and install-persistent, with values and `ff_*` mirror fields |
| `personas.yaml` | Control / Variant A / Variant B and the per-persona probability tables, plus journey constants, search terms, entity pool and fallbacks |
| `crashes.yaml` | Logical crash ids mapped to per-platform impl keys (the `crash_kind` value), with category, expected bitdrift issue type, sweep rules and timings |
| `faults.yaml` | ANR/hang, force-quit, crash loop, fast crash, OOM-only, auto-infinite, slow mode and support: probabilities, timings, target screens, persisted store and key names, startup resume order |
| `api.yaml` | Backend endpoints, path templates, hosts, fake vendor-SDK URLs, SDK release-check URLs, build-time config key names |
| `DECISIONS.md` | Drift decisions (`D-*`) and open questions (`OPEN-*`) |
| `validate.py` | Consistency checker (see below) |

## Validate

```
python3 -m pip install --user pyyaml   # once; PyYAML is the only dependency
python3 spec/validate.py               # --strict also fails on source-line warnings
```

The checker verifies the following:
- Ids and names are unique.
- Every referenced screen, span, event, field, flag, persona and fault exists.
- Platform names are valid, probabilities are in [0, 1] and ranges are ordered.
- Flags and their `ff_*` fields are consistent.
- Every `source:` ref points at an existing file and line.
- Every `used_by:` workflow file exists.
- Every `OPEN-n`/`D-*` id used in YAML is defined in DECISIONS.md.
- (Warning only) The cited source line, within ±3 lines, contains the expected name.

## Schema notes

**Source refs.** Each file declares `source_roots` (for example `A: android/app/src/main/java/ai/bitdrift/shop`).
A ref is `ROOT:path:line`, such as `A:SimulationManager.kt:621`. A `source:` map is keyed
by platform. Line numbers are as of this commit, and the validator flags refs that go
stale.

**Platforms.** The four supported platforms are `android`, `ios`, `reactnative` and `flutter`.
`kmp` (wip-kotlin-multiplatform) is best effort and never validated.

The following keys can appear on events, spans, global fields, flags, faults and crashes:

| Key | Meaning |
|---|---|
| `platforms` | The platforms the item applies to. **Default: all four.** For crashes, the default is the platforms in `impl`. |
| `optional_on` | Platforms *exempt* from the item: an SDK limitation (for example Flutter's alpha SDK has no feature-flag exposure, TTI or Commands API, and no span parenting), or the feature does not exist there by design. Conformance must not fail on these. |
| `missing_on` | Platforms that *should* emit the item but currently do not. This is a work item, not an exemption. Conformance may fail on these until fixed. |
| `drift` | `{platform: current_value}`. The platform emits a different name today and must be renamed to the spec name. Each one has a matching `D-*` entry. |
| `drift_fields`, `drift_level`, `drift_values` | Free-text notes on field, level or value differences that must be fixed. |
| `platform_specific: true` | On a field: its *value* legitimately differs per platform (for example `trigger`, `platform`, `crash_kind`). Excluded from cross-platform stream diffs. |
| `owner: sdk` | On a field: written by the Capture SDK, not the app (for example `_screen_name`, `_span_name`). |
| `used_by` | Committed workflow JSON files that match on this name. **Renaming it means editing those files in the same change.** |
| `open` | Points at an unresolved `OPEN-n` question in DECISIONS.md. |

**Events** (`telemetry.yaml events`):
- `name` is the log message. `level` is `info`/`warning`/`error`/`debug`, or a list if the level varies by outcome.
- `trigger` is `sim`, `ui`, `lifecycle`, `startup`, `fault`, `demo` or `network`.
- `required` and `optional` are field keys, all of which must be in `fields`.
- `message_format` applies when the message embeds values (for example `about_to_crash: {crash_kind} (context={crash_context})`), and `match` gives the regex that workflows use.
- `sim_emits` marks platforms whose simulator emits a `ui` event without a tap (see OPEN-5).

**Spans:**
- `parent` is `null` or the name of another span; the parent graph must be acyclic.
- `fields` are set at start, `end_fields` at end, and `results` lists the possible `SpanResult` values.

**Flags:**
- `kind: persona` defines `values` keyed by persona id.
- `kind: toggle` defines `values: {on, off}` and names the `toggle` (a `faults.yaml` id).
- `kind: persistent` lists `values`, assigned at random once per install. There is a hard cap of 3.
- Each flag has `mirror_field: ff_<name>`, which also appears in `telemetry.yaml global_fields`.

**Personas.** `probabilities.<decision>.<persona_id>` holds one of three shapes:
- a probability, in [0, 1];
- a `weights` map, with relative weights the consumer normalizes;
- a `[min, max]` inclusive range.

**Crashes:**
- `id` is the logical id. `impl` maps each platform to the key the app logs as `crash_kind`.
- `category` and `expected_issue` describe the crash.
- `vendor` references `api.yaml vendor_sdks`.

**Faults:** `store` and `keys` are the per-platform persisted store (an Android
SharedPreferences file or an iOS UserDefaults suite) and its key names. Scripts depend on
these, so treat them as frozen.

## Follow-ups noticed while extracting (not spec changes)
- Persistent flags (`bd-shop-31`) and `support` (`bd-shop-30`) exist only on Android (D-FLG-2).
- A crash-loop resume does not restore the persona on Android or iOS (D-FLT-3).
- Android `previousRunInfo` reporting is plan Phase 6 work (D-EVT-6).
