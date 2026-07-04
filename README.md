# sa-public

**Version 1.0**

Examples and reference material from the bitdrift Solutions Architecture team.

## Important: community-supported, not an official product

The contents of this repository are **community-level contributions provided for
reference and educational purposes only.** They are **not** official bitdrift
products, are **not** part of any bitdrift product offering, and are **not**
covered by any bitdrift service-level agreement, support commitment, or warranty.
Everything here is provided "as is." Review and test any code before adapting it
for your own environment.

For official products, documentation, and support, see the
[bitdrift documentation](https://docs.bitdrift.io) and your standard bitdrift
support channels.

## What's in this repository

### [bitdrift-shop/](bitdrift-shop/)

A full-stack e-commerce demo that generates realistic mobile shopping traffic to
exercise the bitdrift Capture SDK. It includes SDK-instrumented apps for
**Android**, **React Native** (Android + iOS), and **Kotlin Multiplatform**
(Android + iOS), all backed by a shared locally run Docker based **FastAPI** server with a built-in
journey simulator and chaos-testing mode.

### [instrumentation-guide/](instrumentation-guide/)

Platform-neutral guides for instrumenting **any** app with the bitdrift Capture
SDK by **prompting an AI coding agent**. Each step is a ready-to-use prompt that
drives bitdrift's **bd-instrumentation** skill to do the work — write the call
sites, wire the build, and verify it — on Android, iOS, or React Native. You run
the prompts in order; the skill handles the platform-specific details.

Agent and human versions of both are available- the agent version is a focused context doc used for agentic instrumentation of bitdrift capabilities:
- **INSTRUMENTATION_GUIDE.md** and **AGENT_INSTRUMENTATION_GUIDE.md** — a sequenced set of agent prompts to stand up the
  SDK and add screen views, user identity, network capture, structured logs,
  fields, TTI, spans, support tooling, crash symbolication, and log forwarding —
  with the bitdrift feature each prompt unlocks and links to the docs.
- **CLEANUP_GUIDE.md** and **AGENT_CLEANUP_GUIDE.md** — the inverse: prompts that drive the skill to remove the
  instrumentation in reverse order and return an app to its baseline state.

### [misc-demos/](misc-demos/)

Standalone demos and reference artifacts from customer engagements and internal SA work.

- **[manualtracing/](misc-demos/manualtracing/)** — Android app demonstrating manual vs automatic OkHttp network instrumentation with the bitdrift Capture SDK. Shows how both approaches produce identical span structure in the timeline and how `_trace_id` appears on response logs when a tracing workflow is active.

- **[shoppingdemo-oteldemo/](misc-demos/shoppingdemo-oteldemo/)** — Android shopping demo backed by the [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) Telescope Store microservices. Demonstrates OpenTelemetry tracing as well as B3 multi-header trace propagation end-to-end: bitdrift SDK on mobile → OTel Demo backend → Zipkin for visual trace inspection.

- **[metricdemo/](misc-demos/metricdemo/)** — Android app that emits five synthetic waveforms (sine, square, sawtooth, triangle, DC, counter) to bitdrift every second. Used to validate bitdrift chart accuracy against CloudWatch and other metric backends.

- **[pii/](misc-demos/pii/)** — Reference regex configuration and validation artifacts for PII scrubbing via bitdrift's `regex_match_and_substitute_field` filter. Includes the regex YAML, change documentation, and validation test results.
