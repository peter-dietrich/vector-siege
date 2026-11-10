# Vector Siege — development and operations

**Repository:** https://github.com/peter-dietrich/vector-siege  
**Role:** Original first-person vector tank-combat game  
**Minimum runtime:** macOS 13+  
**Technologies:** SwiftUI, SpriteKit, AppKit, AVFoundation  
**Bundle ID:** io.vectorsiege.game

## Application structure

- `VectorSiege.xcodeproj` — native macOS application target and build settings.
- `Sources/` — platform UI, gameplay, rendering, sound and persistence implementation. Browse source filenames in this directory for subsystem boundaries.
- `Resources/` — tracked artwork/audio where present. Validate origin and packaging before any public release.
- `.github/workflows/` — macOS build checks and release automation.
- `README.md` — player-facing setup, controls and change log.

## Supported functionality

Classic and Modern cockpit; rear camera, radar, shield and proximity alarm, architecture and enemies, custom presets, saved battles, 40 shots and 1-second reload by default.

## Local development

1. Install a compatible Xcode version, open `VectorSiege.xcodeproj`, select scheme **VectorSiege** and destination **My Mac**.
2. Use **⌘B** to compile, **⌘R** to play, and **⇧⌘K** after project-file changes when needed.
3. Commit each distinct gameplay or UI change on a feature branch when practical. Keep `main` playable; review and merge via PR.
4. Update README and QA checklist for any control, data format, bundle ID, or release behavior change.
5. Run `git pull --ff-only origin main` in the corresponding checkout to sync; Fun City and each game remain separate repositories.

## Runtime data and integration

Settings, records and saved-game values are maintained locally when supported (typically macOS UserDefaults). They are not stored in GitHub. The game can run standalone; Fun City launches or installs its app bundle rather than compiling its source inside the launcher. Refer to source for exact persistence keys and game-specific edge cases.

## Versioning and compatibility

Treat macOS minimum version, CFBundleIdentifier, save-file format and release asset names as compatibility contracts. Never silently change an existing bundle ID or save format. Note backward-compatibility and migrations in release notes.
