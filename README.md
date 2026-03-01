# ZenML Menu Bar

A native macOS menu bar app for [ZenML](https://zenml.io). Glance at your pipeline runs without leaving what you're doing.

**No browser tabs. No context switching.** Just a small icon in your menu bar that keeps you informed.

## What It Does

- **See your recent runs at a glance** — grouped by status: in progress, failed, then recent
- **Drill into steps** — expand a run to see which step failed or is still running
- **Get notified on failures** — macOS notifications tell you which pipeline (and which step) broke
- **Jump to the dashboard** — one click opens the run in ZenML Pro
- **Stay in sync** — adaptive polling (15s during active runs, 3min when idle) and automatic token refresh

## Install

### Homebrew (recommended)

```bash
brew install --cask zenml-io/tap/zenml-menubar
```

### Manual

Download the latest `.zip` from [GitHub Releases](https://github.com/zenml-io/menubar-zenml/releases), unzip, and drag **ZenML Menu Bar.app** to `/Applications`.

### First Launch

This app is not yet notarized with Apple, so macOS will block it on first launch. Run this once after installing:

```bash
xattr -dr com.apple.quarantine "/Applications/ZenML Menu Bar.app"
```

Then open the app normally. You won't need to do this again.

## Prerequisites

- **macOS 14+** (Sonoma or later)
- **ZenML Pro** account with an active server — the app reads your existing ZenML CLI config, so just make sure `zenml login` works first

## How It Works

The app reads your ZenML CLI configuration from `~/Library/Application Support/zenml/` (or `$ZENML_CONFIG_PATH` if set). It uses the server URL and credentials already stored there — no extra setup needed.

It's **read-only**: it never modifies your config files or makes any changes to your ZenML server.

## Development

### Requirements

- Xcode 16+ (the project uses Swift 5.9+ and SwiftUI with `@Observable`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (optional, for regenerating the project file)

### Build & Run

```bash
# Build from command line
xcodebuild -project ZenMLMenuBar.xcodeproj \
  -scheme ZenMLMenuBar \
  -configuration Debug \
  SYMROOT=build build

# Run
open build/Debug/ZenML\ Menu\ Bar.app
```

Or just open `ZenMLMenuBar.xcodeproj` in Xcode and hit Run.

### Project Structure

```
ZenMLMenuBar/
├── ZenMLMenuBarApp.swift          # Entry point (MenuBarExtra)
├── Models/
│   ├── PipelineRun.swift          # Run data model
│   └── StepRun.swift              # Step data model
├── Services/
│   ├── ZenMLConfigManager.swift   # Config file watching + parsing
│   ├── ZenMLAPIClient.swift       # REST API client with auth
│   ├── PipelineRunStore.swift     # Central state + polling logic
│   └── NotificationManager.swift  # Failure notifications
└── Views/
    ├── RunListView.swift          # Sectioned run list
    ├── RunRow.swift               # Expandable run row
    ├── StepListView.swift         # Inline step list
    ├── StepStatusDot.swift        # Colored status indicator
    └── ...
```

### Architecture

Four layers, each depending only on the one above:

1. **ConfigManager** — reads and file-watches ZenML config/credentials
2. **APIClient** — thin REST client with bearer token auth and 401 retry
3. **PipelineRunStore** — central `@Observable` state driving polling, steps, and notifications
4. **Views** — SwiftUI popover rendering the run list and step drill-down

No third-party dependencies. Pure `URLSession` + SwiftUI + `UserNotifications`.

## License

[Apache 2.0](LICENSE)
