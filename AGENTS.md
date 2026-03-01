# AGENTS.md

## Project

`menubar-zenml` is a native macOS menu bar app for ZenML Pro.

The app is intentionally read-only and acts as a glance layer:
- show recent runs
- highlight failures
- provide fast links to dashboard details

## Current Scope (v0.2)

- Config + credentials watching from `~/Library/Application Support/zenml/`
- Connection verification via `/api/v1/current-user`
- Run list via `/api/v1/runs`
- Expandable run rows with inline actions
- Step drill-down via `/api/v1/runs/{run_id}/steps?project={project_id}`
- Failure notifications (including failed step name when available)
- Adaptive polling (fast when active, slow when idle)

## Architecture

- `ZenMLConfigManager` → config + token refresh
- `ZenMLAPIClient` → REST layer
- `PipelineRunStore` (`@Observable`) → state + polling + notifications + step cache
- `Views/*` → SwiftUI popover UI

## Working Rules

- Keep `LSUIElement = true` in `Info.plist`
- Use `@Observable` (macOS 14+)
- Do not write to ZenML CLI config files
- Preserve dashboard deep-link behavior
- Keep `project.yml` and `ZenMLMenuBar.xcodeproj/project.pbxproj` in sync for new files/settings
- Do not commit anything from `design/` (it is gitignored)

## Build

```bash
xcodebuild -project ZenMLMenuBar.xcodeproj -scheme ZenMLMenuBar -configuration Debug SYMROOT=build build
```

## Regenerate project

```bash
xcodegen generate
```
