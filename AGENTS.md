# Agent Guide for **Selah**

## Overview
Selah is a cross‑platform Bible study app built with **Flutter 3** (Dart ≥3 <4). It targets Android, iOS, Web, Windows, macOS and Linux. The code lives under `lib/` with a conventional Flutter project layout.

## Quick Setup
1. Install Flutter (see https://docs.flutter.dev/install).
2. Run `flutter pub get` to fetch Dart dependencies.
3. The app uses Supabase for optional cloud sync – no env vars are required for a local build, but **if you want sync** set the constants in `lib/supabase_config.dart` (URL & anon key) or create a `.env` and modify the file accordingly.
4. On desktop platforms you may need additional system packages (see CI scripts) – Linux requires GTK3 dev libs, Windows/macOS work out‑of‑the‑box with the Flutter SDK.

## Build & Run Commands
| Platform | Command |
|---|---|
| **All** (dev) | `flutter run` (adds hot‑reload) |
| Android | `flutter build apk --release` |
| iOS | `flutter build ios --release` |
| Web | `flutter build web --release` |
| Windows | `flutter build windows --release` |
| macOS | `flutter build macos --release` |
| Linux | `flutter build linux --release` |
| Linux packaging (deb/rpm/AppImage) | See `.github/workflows/build-all-platforms.yml` – after `flutter build linux` the CI creates packages using `fpm` and `appimagetool`.

> **Gotcha:** The CI extracts the app version from `lib/main.dart` (line with `final appVersion = "…"`). Keep this line in sync with releases.

## Testing
`flutter test` runs any unit tests (project currently has none). Add tests under `test/` and they will be executed automatically by GitHub Actions.

## Project Structure (high‑level)
```
lib/
├─ data/          # Bible text, Strong's definitions, TSK data
├─ database/      # SQLite wrappers for notes, highlights, history, search, Strong's
├─ models/        # Simple data classes (e.g., verse display data)
├─ services/      # Business logic: auth, Supabase sync, imports, change notifier
├─ screens/       # Top‑level UI pages (BibleScreen, SearchScreen, AuthScreen…)
├─ widgets/       # Reusable widgets & dialogs
├─ utils/         # Helpers (color mapping, font size, error handling, platform utils)
├─ main.dart      # App entry point, global notifiers, platform flags
└─ supabase_config.dart
```

## Core Concepts
- **Global `ValueNotifier`s** (e.g., `themeModeNotifier`, `fontSizeNotifier`) drive reactive UI state across the app.
- **Platform detection**: `_isDesktop`, `_isMobilePlatform`, and `kIsWeb` flags are used throughout to branch UI logic.
- **Supabase sync** lives in `services/supabase_sync_service.dart`. It creates realtime channels for notes, highlights, history, and search history. All sync calls guard against `null` user IDs.
- **Auth** in `services/auth_service.dart` wraps Supabase auth APIs and updates the global `isSignedIn` and `currentUser` notifiers.
- **Search** supports three modes (plain, regex, nearby) – see `screens/strongs_search_screen.dart` and `utils/bible_utils.dart` for the implementation.

## Naming & Style Conventions
- Files use **snake_case**; classes use **PascalCase**.
- Global constants are `camelCase` (e.g., `appVersion`).
- Reactive values are `ValueNotifier<T>` with a trailing `Notifier` name.
- UI widgets end with `Widget` or `Dialog` (e.g., `HighlightDialog`).
- Services are singular (`AuthService`, `SupabaseSyncService`).

## Common Gotchas
- **Immediate execution of anonymous functions**: note the `()()` pattern on `isVerticalTile` (line 49‑55). Changing it without the final `()` will break the notifier.
- **Desktop vs Mobile UI**: many widgets check `_isDesktop` or `kIsWeb`. When testing on a non‑desktop platform, those branches are skipped.
- **Supabase channel cleanup**: the sync service disposes streams on sign‑out; forgetting to call `dispose()` can leave dangling listeners.
- **Linux build dependencies**: the CI installs GTK3, libblkid, liblzma, etc. If building locally on Linux, ensure those packages are present or the `flutter build linux` step will fail.
- **Asset paths**: fonts and icons are defined in `pubspec.yaml`. Adding a new asset requires an entry under `flutter/assets` and a `flutter clean` before rebuilding.
- **Version extraction**: CI uses `grep "final appVersion" lib/main.dart`. Do not rename this variable.

## CI / Automation Highlights
- GitHub Actions are defined in `.github/workflows/`. Each platform has its own job that:
  1. Checks out code.
  2. Caches Flutter and pub caches.
  3. Installs platform‑specific build tools.
  4. Runs `flutter clean && flutter pub get`.
  5. Builds the app (`flutter build <platform>`).
  6. Packages the binary (deb, rpm, AppImage, snap, Windows installer, macOS zip).
- Artifacts are uploaded for each run; releases are assembled manually from these packages.

## Helpful Commands for Agents
```bash
# Install deps & generate code
flutter pub get

# Clean build artefacts (important after dependency changes)
flutter clean

# Run on current device (desktop default)
flutter run -d windows   # replace with linux/macOS/web as needed

# Build for distribution
flutter build linux   # same for windows, macos, apk, ios, web

# Run CI locally (requires act or similar)
act -j build-linux
```

## Where to Find More Details
- **Supabase config**: `lib/supabase_config.dart`.
- **Database schemas**: `supabase/supabase_schema.sql`.
- **Platform‑specific packaging**: see `build-all-platforms.yml` and the per‑platform workflow files.
- **Feature flags**: many UI behaviours are toggled via the `ValueNotifier`s near the top of `main.dart`.

---
*Document generated for agents to quickly understand project layout, build workflow, and common pitfalls.*