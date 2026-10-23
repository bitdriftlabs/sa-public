### Wikipedia Android app instrumented with the bitdrift Capture SDK!

This repository contains the source code for our fork of the official [Wikipedia Android app](https://play.google.com/store/apps/details?id=org.wikipedia).

We have instrumented the [bitdrift Capture SDK](https://docs.bitdrift.io/) in this version for mobile observability.

Additional features have been added to support our series of bitdrift hands-on blog-posts. Check them out on the [bitdrift blog](https://blog.bitdrift.io/)! 

### Setup

Add your bitdrift API key to `local.properties` in the repository root (Android Studio creates this file; it is not checked in):

```properties
BITDRIFT_API_KEY=<your API key>
# Optional. Defaults to api.bitdrift.io.
BITDRIFT_API_HOST=api.bitdrift.io
```

Then build and install the dev flavor:

```sh
./gradlew :app:installDevDebug
```

The app uses Capture SDK 0.26.0 with automatic OkHttp and WebView instrumentation (see the `bitdrift` block in `app/build.gradle`).

Long-press the bottom-right corner of any screen for three seconds to open a debug menu that simulates a memory leak, an out-of-memory crash, a native crash (SIGSEGV) and an ANR.

### Documentation

All documentation is kept on [our website](https://docs.bitdrift.io/)). Check it out!

Check out this [hands-on guide](https://blog.bitdrift.io/post/hands-on-wikipedia-android) to instrumenting the Wikipedia app

### Issues

If you have questions or encounter issues, we’d be happy to help. Drop into our [public Slack channel](https://communityinviter.com/apps/bitdriftpublic/bitdrifters) or email us at [info@bitdrift.io](mailto:info@bitdrift.io).
