# Wikipedia iOS
The official Wikipedia iOS app.

[![Wikipedia](https://circleci.com/gh/wikimedia/wikipedia-ios.svg?style=shield)](https://github.com/wikimedia/wikipedia-ios)
[![MIT license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/wikimedia/wikipedia-ios/main/LICENSE.txt)

* **License**: MIT License
* **Source repo**: https://github.com/wikimedia/wikipedia-ios
* **Planning (bugs & features)**: https://phabricator.wikimedia.org/project/view/782/
* **Team page**: https://www.mediawiki.org/wiki/Wikimedia_Apps/Team/iOS

## bitdrift Capture

This copy of the app is instrumented with the [bitdrift Capture SDK](https://docs.bitdrift.io/) 0.51.0. It is upstream [wikipedia-ios](https://github.com/wikimedia/wikipedia-ios) `main` as of 2026-10-22 (`755cd3b242`) plus the bitdrift changes:

- **SDK setup** (`AppDelegate.swift`): starts Capture with the key and host from `BitdriftLocal.xcconfig`, sets the entity ID, enables the URLSession and CocoaLumberjack integrations (swizzling disabled) and registers device commands.
- **WebViews:** instrumented manually (article, link previews and `SinglePageWebViewController`). The article code that clears user scripts keeps the Capture bridge in place.
- **Screen views and launch time:** each main tab logs a screen view; app launch time to interactive is reported.
- **Analytics:** Wikipedia's Event Platform events are also logged to Capture.
- **CUJ demo:** `WikipediaUITests/BitdriftCUJDemoUITests.swift` drives a reading journey.

Create `Configurations/BitdriftLocal.xcconfig` (it is gitignored) with your API key:

```
BITDRIFT_API_KEY = <your API key>
// Optional. Defaults to api.bitdrift.io. Give the host without a scheme.
BITDRIFT_API_HOST = api.bitdrift.io
// Optional. Defaults to demo.
ENTITY_ID = <entity ID>
// Optional. A throwaway Wikipedia test account for the log_in_user command (compiled into the build).
BITDRIFT_DEMO_USERNAME = <test account>
BITDRIFT_DEMO_PASSWORD = <test password>
```

xcconfig treats `//` as the start of a comment, so if your API key contains `//`, write it as `/$()/`. Without an API key the app runs normally but Capture is not started.

Then follow the steps below to build and run.

### Device commands

Run commands from the Device Console or `bd command invoke`. A command must be in your account's command catalog with platform targets that include this app.

| Command | Where it runs | Notes |
| --- | --- | --- |
| `take_screenshot` | Built into the SDK | Works on 0.51.0 |
| `memory_dump <include_heap>` | Built into the SDK | iOS memory snapshot, opens in the Perfetto viewer. Needs an SDK newer than 0.51.0; see below. |
| `flip_flag <flag>` | `AppDelegate.swift` | Toggles a named flag and reports it as a feature flag exposure |
| `open_settings` | `AppDelegate.swift` | Opens Settings as Profile > Settings does |
| `clear_cached_data` | `AppDelegate.swift` | Shows the app's own "Clear cached data?" confirmation |
| `log_out_user` | `AppDelegate.swift` | Logs out at once; the app shows its "you have been logged out" panel. Returns the account type, never the username. |
| `log_in_user` | `AppDelegate.swift` | Logs in with `BITDRIFT_DEMO_USERNAME` and `BITDRIFT_DEMO_PASSWORD` from `BitdriftLocal.xcconfig`, never from arguments |
| `request_app_library` | `AppDelegate.swift` | Shows Help > Export User Data's "Share app library?" consent prompt |
| `fetch_app_library` | `AppDelegate.swift` | Returns the consented app library as a zip attachment, once per consent |

Commands must finish within a few seconds, so the ones that wait for the reader or the network return at once and log their outcome: `clear_cached_data` (`decision`), `log_in_user` (`status`, for example `logged_in`, `needs_email_code`) and `request_app_library` (`app_library_export` with `declined`, `preparing`, `ready` or `failed`). Watch for these in the device's Live Activity log stream.

Android's ANR and OOM crash profiles have no iOS equivalent; they rely on Android's ProfilingManager.

### Testing an unreleased SDK

`Wikipedia.xcodeproj` uses the released Capture SDK. To build against a Capture SDK from a [capture-sdk](https://github.com/bitdriftlabs/capture-sdk) checkout (for example `main`):

```sh
scripts/bitdrift-local-capture /path/to/capture-sdk     # builds the framework there first
scripts/bitdrift-local-capture /path/to/Capture.ios.zip # or use an existing build
```

Then open `Wikipedia-LocalCapture.xcworkspace` instead of the project. Xcode lets the local package in the gitignored `LocalCapture/capture-ios` override the released one. Open `Wikipedia.xcodeproj` again to go back to the released SDK.

### Notes

- **Simulator:** use an iOS 26 simulator. On iOS 18 the app fails to launch (`libswiftWebKit.dylib` not found).
- **Command-line builds:** pass `SIGNING_DISAMBIGUATOR=<your team>` to `xcodebuild` (the value `scripts/setup` writes to `Configurations/OpenSourceDebug.xcconfig`).
- **Upstream sync:** upstream moved to Xcode 27.1 on 2026-10-23, which needs macOS 26.6 or later, so the next sync has to be built with Xcode 27.1.

## Building and Running

Note: Your Xcode version must be at least 16.0.
In the directory, run `./scripts/setup`.  Note: going to `scripts` directory and running `setup` will not work due to relative paths.

Running `scripts/setup` will setup your computer to build and run the app. The script assumes you have Xcode installed already. It will install [homebrew](https://brew.sh), [SwiftLint](https://github.com/realm/SwiftLint), and [ClangFormat](https://clang.llvm.org/docs/ClangFormat.html). It will also create a pre-commit hook that uses ClangFormat for linting Objective-C code.

After running `scripts/setup`, you should be able to open `Wikipedia.xcodeproj` and run the app on the iOS Simulator (using the **Wikipedia** scheme and target). If you encounter any issues, please don't hesitate to let us know via a [bug report](https://phabricator.wikimedia.org/maniphest/task/edit/form/1/?title=[BUG]&projects=wikipedia-ios-app-product-backlog,ios-bug-backlog&description=%3D%3D%3D+How+many+times+were+you+able+to+reproduce+it?%0D%0A%0D%0A%3D%3D%3D+Steps+to+reproduce%0D%0A%23+%0D%0A%23+%0D%0A%23+%0D%0A%0D%0A%3D%3D%3D+Expected+results%0D%0A%0D%0A%3D%3D%3D+Actual+results%0D%0A%0D%0A%3D%3D%3D+Screenshots%0D%0A%0D%0A%3D%3D%3D+Environments+observed%0D%0A**App+version%3A+**+%0D%0A**OS+versions%3A**+%0D%0A**Device+model%3A**+%0D%0A**Device+language%3A**+%0D%0A%0D%0A%3D%3D%3D+Regression?+%0D%0A%0D%0A+Tag++task+with+%23Regression+%0A).

### Required Dependencies
If you'd rather install the development prerequisites yourself without our script:

* [**Xcode**](https://itunes.apple.com/us/app/xcode/id497799835) - The easiest way to get Xcode is from the [App Store](https://itunes.apple.com/us/app/xcode/id497799835?mt=12), but you can also download it from [developer.apple.com](https://developer.apple.com/) if you have an Apple ID registered with an Apple Developer account.
* [**SwiftLint**](https://github.com/realm/SwiftLint) - We use this for linting Swift code.
* [**ClangFormat**](https://clang.llvm.org/docs/ClangFormat.html) - We use this for linting Objective-C code.

## Contributing
Covered in our [contributing documentation](https://www.mediawiki.org/wiki/Wikimedia_Apps/Developing_for_the_apps#Contribute_to_iOS) on MediaWiki.

## Development Guidelines
These are general guidelines rather than hard rules.

### Coding Guidelines
- **Objective-C** - [Apple's Coding Guidelines for Cocoa](https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/CodingGuidelines/CodingGuidelines.html)
- **Swift** - [swift.org API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)

### Formatting
We use Xcode's default 4 space indentation and our `.clang-format` file with the pre-commit hook setup by `scripts/setup`. Where possible, our Swift code is automatically formatted by [SwiftLint](https://github.com/realm/SwiftLint) based on the rules defined in `.swiftlint-autocorrect.yml`.

### Process and Code Review Norms
Covered in the [process document](docs/process.md).

### Logging
When reading logs, note that the log levels are shortened to emoji.
- 🗣️ Verbose
- 💬 Debug
- ℹ️ Info
- ⚠️ Warning
- 🚨 Error

 The app only writes Warning and Error messages to the console for both Debug and Release mode. If you need to log all messages temporarily during troubleshooting, update [this level](https://github.com/wikimedia/wikipedia-ios/blob/main/Wikipedia/Code/WMFLogging.h#L6) to DDLogLevelAll.  

### Testing
The **Wikipedia** scheme is configured to execute the project's iOS unit tests, which can be run using the `Cmd+U` hotkey or the **Product → Test** menu bar action. In order for the tests to pass, the test device's language and region must be set to `en-US` in Settings → General → Language & Region. There is a [ticket filed](https://phabricator.wikimedia.org/T259859) to update the tests to pass regardless of language and region.

### Schemes and Targets

* **Wikipedia** - Points to production servers. 
* **Alpha** -  Points to various staging server environments. You can adjust these environments by changing the `current` [property](WMF%20Framework/Configuration.swift#L41) of `Configuration`:
    - An option of `appsLabsForPCS` will point to the [Apps team's staging environment](https://mobileapps.wmflabs.org) for page content.
    - An option of `betaCluster` will point to the [MediaWiki beta cluster environment](https://www.mediawiki.org/wiki/Beta_Cluster) for most API calls. This is meant to be a more blanket environment setting, so if this value exists it will also force the beta cluster environment for page content on the article view. This beta cluster environment is also where developers can test sandbox push notifications triggered across various wikis. This is selected by default.
    
    The Alpha scheme also has our feature flags set to true. It displays features that are still in development. It is pushed to TestFlight as a separate app.
* **Experimental** - For one-off builds, to demonstrate early development or prototype features. This points to production servers by default, but can be adjusted to whatever server environment is needed via temporary adjustments in `Configuration`. We also sometimes use it for design review, before features go through PR review. It is pushed to TestFlight as a separate app.

* **Local Page Content Service and Announcements** - used by engineers in Debug-mode only. This has the ability to toggle different local environments within the `current` [property](WMF%20Framework/Configuration.swift#L41) of `Configuration`:
    - An option of `localPCS` will point to a locally running [mobileapps](https://gerrit.wikimedia.org/r/q/project:mediawiki%252Fservices%252Fmobileapps) repository for page content. This is selected by default.
    - An option of `localAnnouncements` will point to a locally running [wikifeeds](https://gerrit.wikimedia.org/r/q/project:mediawiki%252Fservices%252Fwikifeeds) repository for the announcements endpoint. This is selected by default.
    -  All other endpoints will point to production.
* **RTL** - Launches the app in an RTL locale using the `-AppleLocale` launch argument. This is used by engineers in Debug-mode only. 
* **Performance Testing** - This is a duplicate scheme of Wikipedia, but uses the Release configuration in its Run step instead of Debug. We use this scheme when we manually run performance tests as a part of our pre-release checklist.  

* **WMF** - Bundles up the app logic shared between the main app and the extensions (widgets, notifications).
* **Update Localizations** - Covered in the [localization document](docs/localization.md).
* **Update Languages** - For adding new Wikipedia languages or updating language configurations. Covered in the [languages document](docs/languages.md).
* **{{name}}Widget, {{name}}Notification, {{name}}Stickers** - Extensions for widgets, notifications, and stickers.

### Continuous Integration
Covered in the [CI document](docs/ci.md).

### Web Development
The article view and several other components of the app rely on web components. Instructions for working on these components are covered in the [web development document](docs/web_dev.md).

### Contact Us
If you have any questions or comments, you can email us at ios-support[at]wikimedia dot org. We'll also gladly accept any [bug reports](https://phabricator.wikimedia.org/maniphest/task/edit/form/1/?title=[BUG]&projects=wikipedia-ios-app-product-backlog,ios-bug-backlog&description=%3D%3D%3D+How+many+times+were+you+able+to+reproduce+it?%0D%0A%0D%0A%3D%3D%3D+Steps+to+reproduce%0D%0A%23+%0D%0A%23+%0D%0A%23+%0D%0A%0D%0A%3D%3D%3D+Expected+results%0D%0A%0D%0A%3D%3D%3D+Actual+results%0D%0A%0D%0A%3D%3D%3D+Screenshots%0D%0A%0D%0A%3D%3D%3D+Environments+observed%0D%0A**App+version%3A+**+%0D%0A**OS+versions%3A**+%0D%0A**Device+model%3A**+%0D%0A**Device+language%3A**+%0D%0A**App+language%3A**+%0D%0A%0D%0A%3D%3D%3D+Regression?+%0D%0A%0D%0A+Tag++task+with+%23Regression+%0A).
