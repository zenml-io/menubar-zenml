# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A native macOS menu bar app for ZenML Pro. Shows pipeline run status in a
popover, includes step-level drill-down, sends failure notifications, and deep-links to the ZenML dashboard.
Read-only — it's a "glance layer," not a dashboard replacement.

- **Framework:** SwiftUI `MenuBarExtra(.window)`, macOS 14+ (Sonoma)
- **Dependencies:** None — pure URLSession + SwiftUI
- **Entry point:** `ZenMLMenuBar/ZenMLMenuBarApp.swift`

## Current Status

v0.2 is implemented in `ZenMLMenuBar/`:
- Expandable run rows (row click toggles expand/collapse)
- Inline step list drill-down (lazy loaded, capped at 10 inline steps)
- Copy Run ID action
- Notification enrichment with failed step name when available
- Build/release workflow scaffold for phased Homebrew distribution

## Build & Run

```bash
# Build from command line
xcodebuild -project ZenMLMenuBar.xcodeproj -scheme ZenMLMenuBar -configuration Debug SYMROOT=build build

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
2. **ZenMLAPIClient** — Thin URLSession REST client. Bearer token auth. Endpoints: `/api/v1/current-user`, `/api/v1/runs`, `/api/v1/runs/{id}/steps`. Handles 401→refresh→retry.
3. **PipelineRunStore** (`@Observable`) — Central state. Holds run list, connection state, cached data, per-run step loading state, and notification/failure tracking. Drives adaptive polling (15s when runs active, 3min when idle).
4. **SwiftUI Views** — `MenuBarExtra(.window)` popover: ConnectionStrip → RunListView (sectioned: In Progress/Failed/Recent) → expandable RunRow with actions + optional StepListView → Footer.

## Design Documents

All design docs live in `design/` (gitignored — not committed). Read before making UI or architecture changes:

- `design/v0.2_plan.md` — v0.2 scope: step drill-down + phased distribution plan
- `design/implementation_plan.md` — baseline architecture, data models, API endpoints, scope guardrails
- `design/ui_notes.md` — validated visual specs: colors, spacing, dark/light mode, status styles, state presentations
- `design/initial_plan_idea_clean.md` — product background and rationale
- `design/zenml-menubar-playground.html` — interactive UI prototype
- `design/agent_implementation_prompt.md` — implementation sequencing prompt

## Key Conventions

- `Info.plist` must have `LSUIElement = true` (hides from Dock)
- Use `@Observable` macro (not `ObservableObject`/`@Published`) — requires macOS 14+
- Config files at `~/Library/Application Support/zenml/` — never write to these, read-only
- Token refresh: POST Pro API token to workspace server's `/api/v1/login` with `grant_type=zenml-external`
- Step endpoint requires project scope: `/api/v1/runs/{run_id}/steps?project={project_id}`
- Dashboard deep links: `{pro_dashboard_url}/workspaces/{workspace_name}/projects/{project_id}/runs/{run_id}`
- v0.2 row behavior is intentional: clicking a run row expands it (not direct open)
- Dark mode: white menu bar icons, white ZenML logo. Light mode: dark icons, original purple logo
- Status pill colors: running=blue (pulse), failed=red, completed=green, cached=grey

## Scope Boundary

v0.2 scope includes config watching, server connection, run fetching/display,
step drill-down, failure notifications (with optional step-name enrichment), adaptive polling, badge dot, dashboard deep links, stale-data display, and token refresh.

Out-of-scope for now: full settings UI, server switcher, Sparkle auto-update, and additional v0.3+ enhancements listed in `design/v0.2_plan.md`.

## Repo Note

Repo-specific agent guidance is available in `AGENTS.md`.
