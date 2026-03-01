# ZenML Menu Bar (v0.2)

A native macOS menu bar app for ZenML Pro.

It provides a fast, glanceable view of recent runs and failures, then deep-links to the ZenML dashboard for deeper investigation.

## Features (v0.2)

- Reads `config.yaml` + `credentials.yaml` on launch
- Watches both files for live changes
- Verifies server connection via `GET /api/v1/current-user`
- Fetches recent runs via `GET /api/v1/runs?sort_by=desc:created&size=20&hydrate=false`
- Groups runs in the popover: **In Progress → Failed → Recent**
- Expandable run rows with inline action bar
  - Open in Dashboard
  - Copy Run ID
  - Show/Hide steps
- Step-level drill-down via `GET /api/v1/runs/{run_id}/steps?project={uuid}&size=200&hydrate=false`
  - Shows up to 10 steps inline
  - Offers "Show all N steps in Dashboard" for longer runs
- Sends macOS notifications on failure transitions
  - Includes failed step name when available
- Shows red badge dot on menu bar icon for unacknowledged failures
- Adaptive polling: **15s when active runs exist, 3m when idle**
- Displays active project name in the connection strip
- Shows cached data dimmed while refreshing or reconnecting
- Supports token refresh (`grant_type=zenml-external`) on auth expiry
- Includes a Quit action in the footer

## Install

### Homebrew (recommended)

```bash
brew install --cask zenml-io/tap/zenml-menubar
```

Tap repository: https://github.com/zenml-io/homebrew-tap

### Manual

Download the latest `.zip` from GitHub Releases, unzip, and drag **ZenML Menu Bar.app** to `/Applications`.

Phase 1 distribution is not notarized yet. On first launch, you may need to right-click the app and choose **Open**.

## Requirements

- macOS 14+ (Sonoma)
- Xcode 15+ (for local builds)

## Build

```bash
xcodebuild -project ZenMLMenuBar.xcodeproj -scheme ZenMLMenuBar -configuration Debug SYMROOT=build build
```

## Run

```bash
open build/Debug/ZenML\ Menu\ Bar.app
```

If Xcode reports stale-file warnings from old DerivedData outputs, you can ignore them or clean once:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/ZenMLMenuBar-*
```

Or open in Xcode:

```bash
open ZenMLMenuBar.xcodeproj
```

## Configuration Source

The app reads ZenML CLI config files from:

- Default: `~/Library/Application Support/zenml/`
  - `config.yaml`
  - `credentials.yaml`
- Override: `ZENML_CONFIG_PATH` (if set)

The app is **read-only** with respect to these files.

## Notes

- `LSUIElement=true` is set so the app stays in the menu bar and does not show in the Dock.
- No third-party runtime dependencies are used (`URLSession` + SwiftUI + UserNotifications).
- Repo-specific agent guidance is documented in `AGENTS.md`.
