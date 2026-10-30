# EDGE Work Dashboard

Native macOS shell for the 2560×720 CORSAIR XENEON EDGE work dashboard.

## Features

- resolves and remembers the physical EDGE display;
- owns a borderless dashboard window on that display;
- renders a touch-first WKWebView interface;
- reads live status from the independent touch driver;
- reports live aggregate CPU load, memory use, and system uptime;
- provides native Preferences for display, editor, terminal, and workspace configuration;
- supports any number of workspaces with add, edit, delete, reorder, colour, label, and start-workspace controls;
- nests any number of folders inside each workspace, including multi-folder selection and reassignment;
- supports full macOS colour pickers for both workspaces and folders;
- manages an ordered, user-configurable list of macOS applications with enable, rename, default, and remove controls;
- assumes no third-party applications are installed; fresh setups start with Finder and folder menus only show apps available on that Mac;
- offers the enabled applications plus the configured terminal as per-folder actions;
- supports per-folder application visibility, ordering, defaults, and one-tap editor/terminal launch recipes;
- guides new installations through workspace, folder, and application setup;
- optionally registers the installed app with macOS Launch at Login and links directly to approval settings when required;
- imports and exports portable JSON configuration backups without machine-specific display IDs or security bookmarks;
- keeps a floating touch target available to return to the dashboard.

No user names or workspace paths are built into the application. Configuration
is stored per user at
`~/Library/Application Support/EDGE Work Dashboard/preferences.json` and is not
included in the app bundle or repository.

### Folder actions

Tapping a folder opens a touch-friendly chooser. Editor and Finder actions open
that exact folder in the selected application. Terminal actions create a new
window at that folder in iTerm2 or macOS Terminal, according to Preferences.

## Run locally

The full Xcode toolchain is required on this workstation:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run
```

Build a standalone macOS app bundle:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build-app.sh
open ".build/app/EDGE Work Dashboard.app"
```

The development bundle uses an ad-hoc signature. Distribution will use a
stable Developer ID identity, hardened runtime, and notarisation in the
hardening phase.

Promote the current build to the per-user Applications folder and relaunch it:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/install-app.sh
```

The installer replaces only `~/Applications/EDGE Work Dashboard.app` and keeps
preferences because the bundle identifier remains
`com.nocreativity.EdgeWorkDashboard`. Supply `CODESIGN_IDENTITY` to both build
and installation when a stable Apple Development or Developer ID identity is
available; otherwise the development build is ad-hoc signed.

The first per-folder terminal launch may trigger macOS Automation approval for
controlling the selected terminal. The dashboard does not accept arbitrary
shell commands from the web surface; all native actions are allowlisted in
Swift.
