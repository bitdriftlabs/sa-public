# sa-public

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

Platform-neutral guides for working with the bitdrift Capture SDK in **any** app:

- **INSTRUMENTATION_GUIDE.md** — a step-by-step checklist for wiring up the SDK,
  with each step mapped to the product feature it unlocks (Android examples, plus
  iOS and React Native API maps).
- **CLEANUP_GUIDE.md** — how to cleanly remove the SDK and return an app to its
  baseline state.
