# tools/journey: the shared journey engine

The simulated shopping journey is data, in [`spec/journey.yaml`](../../spec/journey.yaml).
Each app runs it through a small interpreter. The interpreters are ports of one
reference, so the same persona and seed produce the same journey on every app.

| File | What it does |
|---|---|
| `compile.py` | Validates `spec/journey.yaml` and resolves every reference: personas.yaml decisions and constants, faults.yaml, flags, screens and route params, events and their required fields, spans and their parents, endpoints, and variables. It writes the normalized bundle that `tools/codegen` embeds in each app. |
| `engine.py` | The reference interpreter and the `TraceAdapter` used to produce golden traces. |
| `golden.py` / `golden.json` | The exact adapter-call trace per seeded case, run against a canned backend (`test_fixture` in journey.yaml). `tools/codegen/generate.sh` rewrites it and `check.sh` fails if it is stale. |

The interpreters and their golden-trace tests:

| App | Engine | Golden test |
|---|---|---|
| android | `android/.../JourneyEngine.kt` | `JourneyEngineTest.kt` (JVM, unit tier) |
| ios | `ios/BitdriftShop/JourneyEngine.swift` | `ios/scripts/test-journey-engine.sh` (swiftc on the host) |
| reactnative | `reactnative/src/sim/journeyEngine.ts` | Jest |
| flutter | `flutter/lib/sim/journey_engine.dart` | `flutter test` |

## Changing the journey

1. Edit `spec/journey.yaml`, or a number in `spec/personas.yaml` or `spec/faults.yaml`.
2. Run `tools/codegen/generate.sh`. This regenerates every app's bundle and `golden.json`.
3. Run `./test.sh all unit`. Every app's engine must still replay the new golden traces.
   If a test fails here, an interpreter has drifted from `engine.py`. The YAML is not the
   cause.

You never edit an interpreter to change behaviour. Change an interpreter only to add a
new op, and change `engine.py`, `compile.py` and all four ports in the same commit.

## Bundle (what the interpreters read)

```
{version, step_delay_ms, entities: [..],
 personas: {<id>: {vars: {variant: <label>, "flag.<name>": <value>, ..}}},
 journey: [op, ..]}
```

The compiler inlines procedures (`call`). It also replaces every probability, weight and
range with a per-persona table, so an interpreter only looks up `table[persona]`. The ops
are the ones listed in the journey.yaml header, each with an `"op"` key:

| op | keys |
|---|---|
| `new_session`, `exposures`, `entity` | none |
| `wait` | `ms` |
| `nav` | `screen`, `args` |
| `api` | `endpoint`, `args`, `save: [{var, key, item?, default}]` (`item` set means a list of `key[].item`) |
| `log` | `level`, `event`, `fields` |
| `span_start` | `span`, `parent`, `fields` |
| `span_end` | `span`, `result`, `fields` |
| `span` | `span`, `parent`, `fields`, `do` |
| `set` | `values` |
| `pick` | `into`, `from` or `values`, `exclude?` |
| `rand_int` | `into`, `min`, `max` |
| `choose` | `into`, `weights: {persona: [[key, w], ..]}`, `branches` |
| `if` | `chance?: {default: {persona: p}, by?, cases?}`, `toggle?`, `not_toggle?`, `eq?`, `min_len?`, `then`, `else` |
| `switch` | `var`, `cases`, `default` |
| `repeat` | `ranges: {persona: [lo, hi]}`, `do` |
| `for_each` | `list`, `as`, `do` |
| `list_add` | `list`, `value` |
| `list_remove_random` | `list`, `into` |
| `list_clear` | `list` |
| `last` | `list`, `into`, `default` |
| `fault` | `fault`, `probability`, `force_after`, `level`, `event`, `fields` |
| `crash_point` | `point` |
| `stop` | `outcome` |

## Adapter (what each app implements)

`isCancelled`, `startNewSession`, `applyExposures(persona)`, `setEntity`, `delay(ms)`,
`navigate(screen, args)`, `callApi(endpoint, args) -> JSON | null`,
`log(level, event, fields)`, `startSpan(name, parentHandle, fields) -> handle`,
`endSpan(handle, result, fields)`, `addField`, `injectFault(id)` and `fireCrash()`.

Faults and crashes are split between the two sides. The engine rolls the dice, logs
`*_injected` and sets `crash_journey_point`. The adapter performs the platform mechanism:
it persists the restart intent, then blocks the main thread, exits, or fires the next
crash-loop crash.

## Trace line format (golden.json)

Each adapter call becomes one line. Fields are sorted by key and written `{k=v, k=v}`.

```
new_session | exposures <persona> | entity <id> | wait <ms> | nav <screen> {args}
api <endpoint> {args} | log <level> <event> {fields}
span_start <span> <parent span name | -> {fields} | span_end <span> <result> {fields}
field <key>=<value> | fault <id> | crash | outcome <outcome>   (outcome is appended by the runner)
```

## Device recordings

`tools/conformance/conformance.py --persona P --seed S --runs N` re-runs `engine.py` for
the same persona and seed, then requires the app's recorded journey records to match:
the events and spans that journey.yaml emits, in order, with parent span names. Fields in
`volatile_fields` (values the backend generates at random) and `platform_specific`
fields are excluded from the comparison. `--diff a.jsonl b.jsonl ..` compares two or more
apps directly. `./test.sh all smoke` runs both checks.
