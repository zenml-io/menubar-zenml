# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A native macOS menu bar app for ZenML Pro. Shows pipeline run status in a
popover, sends failure notifications, and deep-links to the ZenML dashboard.
Read-only — it's a "glance layer," not a dashboard replacement.

- **Framework:** SwiftUI `MenuBarExtra(.window)`, macOS 14+ (Sonoma)
- **Dependencies:** None — pure URLSession + SwiftUI
- **Entry point:** `ZenMLMenuBar/ZenMLMenuBarApp.swift`

## Current Status

MVP v0.1 implementation is present in `ZenMLMenuBar/` with the full models/services/views structure described below.

## Build & Run

```bash
# Build from command line
xcodebuild -project ZenMLMenuBar.xcodeproj -scheme ZenMLMenuBar -configuration Debug build

# Run (after building)
open build/Debug/ZenML\ Menu\ Bar.app

# Or open in Xcode
open ZenMLMenuBar.xcodeproj
```

If project files need to be regenerated, use:

```bash
xcodegen generate
```

## Architecture

Four layers, each depending only on the one above it:

1. **ZenMLConfigManager** — Reads and file-watches `~/Library/Application Support/zenml/config.yaml` and `credentials.yaml`. Emits change notifications. Handles token refresh via Pro API.
2. **ZenMLAPIClient** — Thin URLSession REST client. Bearer token auth. Endpoints: `/api/v1/current-user`, `/api/v1/runs`. Handles 401→refresh→retry.
3. **PipelineRunStore** (`@Observable`) — Central state. Holds run list, connection state, cached data. Drives adaptive polling (15s when runs active, 3min when idle). Detects failure transitions → triggers notifications.
4. **SwiftUI Views** — `MenuBarExtra(.window)` popover: ConnectionStrip → RunListView (sectioned: In Progress/Failed/Recent) → Footer.

## Design Documents

All design docs live in `design/` (gitignored — not committed). Read before making UI or architecture changes:

- `design/implementation_plan.md` — Architecture, data models, API endpoints, MVP scope, project structure
- `design/ui_notes.md` — Validated visual specs: colors, spacing, dark/light mode, status pills, icon states, state presentations
- `design/initial_plan_idea_clean.md` — Background context and product rationale
- `design/zenml-menubar-playground.html` — Open in browser to see the UI prototype live
- `design/agent_implementation_prompt.md` — Full implementation prompt with build order

## Key Conventions

- `Info.plist` must have `LSUIElement = true` (hides from Dock)
- Use `@Observable` macro (not `ObservableObject`/`@Published`) — requires macOS 14+
- Config files at `~/Library/Application Support/zenml/` — never write to these, read-only
- Token refresh: POST Pro API token to workspace server's `/api/v1/login` with `grant_type=zenml-external`
- Dashboard deep links: `{pro_dashboard_url}/workspaces/{workspace_name}/projects/{project_id}/runs/{run_id}`
- Dark mode: white menu bar icons, white ZenML logo. Light mode: dark icons, original purple logo
- Status pill colors: running=blue (with pulse animation), failed=red, completed=green, cached=grey

## MVP Scope Boundary

v0.1 is strictly: config reading, file watching, server connection, run fetching/display, failure notifications, adaptive polling, badge dot, dashboard deep links, stale data display, token refresh. See `design/implementation_plan.md` "MVP Scope" and "Out of scope" sections for the explicit boundary — do not implement v0.2 features.
