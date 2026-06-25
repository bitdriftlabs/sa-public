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
(Android + iOS), all backed by a shared **FastAPI** server with a built-in
journey simulator and chaos-testing mode.

### [instrumentation-guide/](instrumentation-guide/)

Platform-neutral guides for instrumenting **any** app with the bitdrift Capture
SDK by **prompting an AI coding agent**. Each step is a ready-to-use prompt that
drives bitdrift's **bd-instrumentation** skill to do the work — write the call
sites, wire the build, and verify it — on Android, iOS, or React Native. You run
the prompts in order; the skill handles the platform-specific details.

- **INSTRUMENTATION_GUIDE.md** — a sequenced set of agent prompts to stand up the
  SDK and add screen views, user identity, network capture, structured logs,
  fields, TTI, spans, support tooling, crash symbolication, and log forwarding —
  with the bitdrift feature each prompt unlocks and links to the docs.
- **CLEANUP_GUIDE.md** — the inverse: prompts that drive the skill to remove the
  instrumentation in reverse order and return an app to its baseline state.
