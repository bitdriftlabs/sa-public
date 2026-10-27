# One spec, four apps

Part of the [bitdrift Shop README](../README.md).

The apps share data, not code. [`spec/`](../spec/README.md) holds the screens, event, field and span names, feature flags, persona probabilities, and the journey itself. Each app is built from it:

- **Generated constants:** every name an app logs comes from `spec/` (`tools/codegen`), so the platforms cannot drift apart.
- **One journey, run everywhere:** each app interprets [`spec/journey.yaml`](../spec/journey.yaml) with a small engine. Change a probability or a step once, run `tools/codegen/generate.sh`, and all four apps behave differently together.
- **Reproducible and checked:** the same persona and seed give the same journey on every app. `./test.sh all unit` replays golden traces on every engine. `./test.sh all smoke` runs each app on a device, checks its recording against the reference engine, and diffs the apps against each other.

The apps themselves stay idiomatic Kotlin, Swift, TypeScript and Dart, so each one still reads like a normal customer app.

See [`spec/README.md`](../spec/README.md) for the files themselves, [`spec/DECISIONS.md`](../spec/DECISIONS.md) for how
cross-platform drift was resolved, and [`tools/journey`](../tools/journey/README.md) for the journey engine.
