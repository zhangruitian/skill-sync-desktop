# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Build & Run

```bash
# Full compile (all 23 Swift files, arm64)
swiftc -parse-as-library \
    -framework SwiftUI -framework Combine -framework AppKit \
    -target arm64-apple-macos13.0 \
    -o SkillSyncDesktop \
    SkillSyncDesktop/*.swift \
    SkillSyncDesktop/Models/*.swift \
    SkillSyncDesktop/Services/*.swift \
    SkillSyncDesktop/Views/*.swift \
    SkillSyncDesktop/Views/Components/*.swift
```

To open in Xcode for GUI work, install `xcodegen` (`brew install xcodegen`), run `./setup-xcode.sh`, then `open SkillSyncDesktop.xcodeproj`.

There are no tests yet — this app was scaffolded from scratch based on [docs/sync-skills.sh](docs/sync-skills.sh) and [docs/README.md](docs/README.md).

## Architecture

**Pattern**: MVVM with services. `SkillSyncViewModel` is the single `@MainActor` coordinator, owning all services and `@Published` state. Views bind to it and never talk to services directly.

**Data flow**:
```
AppSettings (UserDefaults-backed @Published)
         │
         ▼
SkillSyncViewModel ──owns──▶ HubManager, AgentManager, StatusEngine,
                            SyncEngine, DiffEngine, WatchEngine, BackupCleaner
         │
         ▼
Views (ContentView → StatusView / DiffView / SettingsView)
```

**Key design decisions**:

- **Sendable**: Services are `@unchecked Sendable` to allow background dispatch. The ViewModel captures them by local copy before entering `DispatchQueue.global()` closures to satisfy Swift 6 concurrency — follow this pattern when adding background work.
- **State detection** (`StatusEngine`): For each `skill × agent` pair, checks: symlink target resolution → directory content comparison (SKILL.md first, then full `diff -rq` with ignore patterns). Mirrors the shell script's `get_skill_state()`.
- **Sync operations** (`SyncEngine`): `link` mode uses `ln -sfn`; `copy` mode copies then strips dev files matching `ignoreGlobs`. Always backs up existing targets as `*.backup-<timestamp>` when `autoBackup` is true.
- **Watch mode** (`WatchEngine`): Uses FSEvents C API wrapped in `FileSystemEventStream`. On events, checks file mtimes (5s window), debounces 2s per-skill, then auto-syncs. The FSEvents API uses raw `kFSEventStream*` constants because Swift doesn't import them as enum members — do not try to use `.fileEvents` dot syntax.
- **App settings** (`AppSettings`): Singleton backed by `UserDefaults`. Publishes changes via `@Published`. Agents list and hub profiles are JSON-encoded; ignore patterns are string arrays. Default agents: Codex (`~/.Codex/skills`), codex (`~/.codex/skills`), agents (`~/.agents/skills`).
- **Error handling** (`AppError`): Unified error model with info/warning/error severity, captured by the ViewModel's `errors` array for structured error reporting.

**Views**: `ContentView` is the `NavigationSplitView` root (sidebar + detail). `StatusView` shows the skill×agent matrix with checkboxes for batch sync. `DiffView` is a sheet for per-file comparisons. `TerminalView` is a panel for running the reference shell script with streaming output. `SettingsView` is a sheet with tabbed Form sections.

## Relevant docs

- [docs/README.md](docs/README.md) — user guide for the shell script, documents all commands and behavior
- [docs/sync-skills.sh](docs/sync-skills.sh) — reference bash implementation; all business rules (state detection, sync logic, exclude patterns, backup naming) originate here
