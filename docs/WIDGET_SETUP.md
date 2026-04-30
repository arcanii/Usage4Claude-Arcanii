# Adding the Widget Extension target (Xcode UI)

The widget code is already on disk (`WidgetExtension/`, `Config/Usage4Claude.entitlements`, `Usage4Claude/Helpers/UsageSnapshot.swift`), and `DataRefreshManager` already writes the App Group snapshot + nudges `WidgetCenter.shared.reloadAllTimelines()` on each fetch. What's missing is the `.xcodeproj` target definition and the App Group capability on the main app.

The pbxproj surgery for a brand-new target with App Group entitlements is fragile — Xcode's auto-signing has to register this Mac with your Apple Developer account and provision new bundle IDs (`com.arcanii.Usage4Claude` for the App Group, `com.arcanii.Usage4Claude.Widget` for the widget). The Xcode UI does this in five clicks; the command-line equivalent fights provisioning errors. So we ship the source ready-to-go and let you finish the wiring in Xcode.

## Steps

### 1. Add the App Group capability to the main app

1. Open `Usage4Claude.xcodeproj` in Xcode.
2. Select the **Usage4Claude** target → **Signing & Capabilities**.
3. Click **+ Capability** → **App Groups**.
4. Click the **+** under "App Groups" and enter:
   ```
   group.com.arcanii.Usage4Claude
   ```
5. Xcode will register the group with your developer account and sign the app.
6. **Replace** the auto-generated entitlements file: Build Settings → "Code Signing Entitlements" → set to `Config/Usage4Claude.entitlements` (the file is already in the repo with the right content).

### 2. Add the Widget Extension target

1. **File** → **New** → **Target…** → **Widget Extension**.
2. Settings:
   - Product Name: `Usage4ClaudeWidget`
   - Team: same as main app (Matthew Mark — `386M76FV3K`)
   - Bundle Identifier: `com.arcanii.Usage4Claude.Widget`
   - Include Configuration App: **No**
   - Include Live Activity: **No**
3. Xcode creates a `Usage4ClaudeWidget/` folder with stub files. **Delete** those stubs (the `Usage4ClaudeWidget.swift`, the `Assets.xcassets`, and the entitlements file Xcode generated).
4. In the Project Navigator, **right-click the Usage4ClaudeWidget group** → **Add Files to "Usage4Claude"…** → select `WidgetExtension/Usage4ClaudeWidget.swift`, `WidgetExtension/Info.plist`, and `WidgetExtension/Usage4ClaudeWidget.entitlements`. Make sure they're added to the **Usage4ClaudeWidget** target.
5. Select the **Usage4ClaudeWidget** target → **Build Settings**:
   - Set **Info.plist File** to `WidgetExtension/Info.plist`.
   - Set **Generate Info.plist File** to **No**.
   - Set **Code Signing Entitlements** to `WidgetExtension/Usage4ClaudeWidget.entitlements`.
   - Confirm **Deployment Target** is `26.0` (matches main app).

### 3. Add App Group capability to the widget

1. Select the **Usage4ClaudeWidget** target → **Signing & Capabilities** → **+ Capability** → **App Groups**.
2. Check the box for `group.com.arcanii.Usage4Claude` (Xcode will offer it from step 1).

### 4. Share `UsageSnapshot.swift` with the widget target

1. In the Project Navigator, find `Usage4Claude/Helpers/UsageSnapshot.swift`.
2. Open the **File Inspector** (right pane).
3. Under **Target Membership**, check **Usage4ClaudeWidget** (it should already be checked for **Usage4Claude**).

`UsageSnapshotBridge.swift` (which references `UsageData`) should remain in the main target only.

### 5. Build and verify

- Build the **Usage4Claude** scheme (Product → Build, or `⌘B`). The widget extension builds as part of the main app's dependency graph.
- Run the app, ensure your usage data fetches successfully (so the snapshot file gets written to the App Group container).
- Add the widget to your desktop: right-click on the desktop → **Edit Widgets…** → search for "U4Claude" or "Claude Usage" → drag the small or medium variant onto the desktop.

The widget reads from `~/Library/Group Containers/group.com.arcanii.Usage4Claude/usage-snapshot.json`. If you want to verify it directly:

```bash
cat "$HOME/Library/Group Containers/group.com.arcanii.Usage4Claude/usage-snapshot.json" | jq
```

## What's already done in the repo

- `Usage4Claude/Helpers/UsageSnapshot.swift` — Codable snapshot type + read/write via `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
- `Usage4Claude/Helpers/UsageSnapshotBridge.swift` — `UsageSnapshot.init(from: UsageData)`.
- `DataRefreshManager.fetchUsage` success path writes the snapshot and calls `WidgetCenter.shared.reloadAllTimelines()`.
- `WidgetExtension/Usage4ClaudeWidget.swift` — `@main` widget bundle, `StaticConfiguration`, `TimelineProvider`, small + medium SwiftUI views.
- `WidgetExtension/Info.plist` — extension Info.plist (`NSExtension` → `NSExtensionPointIdentifier` = `com.apple.widgetkit-extension`).
- `WidgetExtension/Usage4ClaudeWidget.entitlements` — sandbox on, App Group, no network.
- `Config/Usage4Claude.entitlements` — main app entitlements (sandbox off, App Group).

## Why command-line `xcodebuild` couldn't do this

`Apple Development` provisioning profiles for new bundle IDs require the build machine to be registered in your developer account, which is an interactive step (signing in to your Apple ID in Xcode → Preferences → Accounts → Manage Certificates). `Developer ID Application` signing for an extension that uses App Groups requires a Developer ID provisioning profile that includes the App Group capability — generated through the Apple Developer portal (or auto-managed by Xcode). Either path needs Xcode UI at least once to set up. After the initial Xcode-driven signing, future builds via `./scripts/build.sh` work fine because the profiles are now cached locally.
