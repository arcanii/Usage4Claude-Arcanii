# Tests

Unit tests for pure functions extracted from the Xcode app target. The tests run via SwiftPM, not via the Xcode project — the `.xcodeproj` stays the authoritative app build, while `Package.swift` at the repo root carves out a small library + test target for code that can be exercised without AppKit, Bundle resources, or live network.

## Running

```bash
swift test
```

If you see `no such module 'XCTest'`, your `xcode-select` points at CommandLineTools instead of the full Xcode. Either fix it system-wide:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

…or prefix the command:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Adding tests

1. Identify a piece of logic in the app that doesn't depend on `AppKit` / `Bundle.main` / `URLSession` / SwiftUI — i.e. a pure function or a struct with `Codable` parsing.
2. If it's currently embedded in a class with side effects, extract it into its own file under `Usage4Claude/Helpers/` (e.g. `SemverCompare.swift` was carved out of `UpdateChecker`).
3. Add the new file to `Package.swift`'s `Usage4ClaudeCore` target `sources` list:

   ```swift
   .target(
       name: "Usage4ClaudeCore",
       path: "Usage4Claude/Helpers",
       sources: ["SemverCompare.swift", "YourNewFile.swift"]
   ),
   ```

4. Write the test in `Tests/Usage4ClaudeCoreTests/` and run `swift test`.

## What's currently covered

- **`SemverCompare`** — version parsing (`v1.2.3` → `1.2.3`) and `isNewerVersion` ordering for major/minor/patch, equal versions, padding short versions with zeros, and the v1.0.0 → v1.1.0 update-detection case that motivated this extraction.

## What's not covered (yet)

The bigger wins would be tests for `UsageResponse.toUsageData()` and `ExtraUsageResponse.toExtraUsageData()` — both are pure JSON → struct transformations with non-trivial fallback logic for legacy fields. They live in `ClaudeAPIService.swift` today, which imports OSLog and references settings; extracting just the response models into their own file would unlock testing them here.
