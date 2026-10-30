# EDGE Work Dashboard

A local-first macOS dashboard and touch-routing driver for the CORSAIR XENEON EDGE.

This monorepo contains:

- [`dashboard-app`](dashboard-app): a native AppKit/SwiftUI application with a touch-first WKWebView dashboard.
- [`touch-driver`](touch-driver): the independent macOS touchscreen routing driver.
- [`docs`](docs): architecture, permissions, and hardware setup notes.

## Current capabilities

- Finds and remembers the dashboard display.
- Routes EDGE touch input correctly across multi-display macOS setups.
- Supports configurable Workspaces containing any number of Folders.
- Opens folders in user-managed macOS applications or a configured terminal.
- Supports per-folder application ordering, defaults, and launch recipes.
- Reports live CPU, memory, uptime, and touch-driver health.
- Provides native Preferences, first-run setup, Launch at Login, and portable configuration backup.

## Requirements

- macOS 13 or newer.
- Full Xcode installation for source builds.
- CORSAIR XENEON EDGE for the intended hardware experience.
- Accessibility and Input Monitoring approval for the touch driver.
- Automation approval when controlling a terminal application.

## Build and test

Run every test suite:

```sh
./Scripts/test-all.sh
```

Build, install, and launch the dashboard for the current user:

```sh
./dashboard-app/Scripts/install-app.sh
```

Install the touch driver:

```sh
./touch-driver/Scripts/install.sh
```

The driver installation and dashboard installation remain separate so macOS permission prompts are explicit.

## User configuration

Dashboard preferences are stored at:

```text
~/Library/Application Support/EDGE Work Dashboard/preferences.json
```

Machine-specific preferences are not part of this repository. Preferences can export a portable JSON configuration that excludes display identifiers, application paths, and security bookmarks.

## Repository status

The project is under active hardware-driven development. The touch driver retains its existing MIT license and attribution in [`touch-driver/LICENSE`](touch-driver/LICENSE). A repository-wide license for the dashboard and combined distribution must be selected before the first public release.
