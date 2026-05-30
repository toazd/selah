# 🤖 Selah Codebase Agent Guide (AGENTS.md)

This document provides non-obvious architectural knowledge and conventions for AI agents working within the Selah codebase.

## 🏗️ Architecture & Structure

The codebase is a cross-platform Flutter application built around a clean separation of concerns:

*   **`lib/` (Core Logic):** Contains the main application code.
    *   **`lib/screens/`:** UI components and full screen views (e.g., `bible_screen.dart`, `search_screen.dart`).
    *   **`lib/services/`:** The business logic layer. This layer handles external interactions (APIs, file I/O, state changes). Key services include:
        *   `AuthService`: User authentication.
        *   `SupabaseSyncService`: Handles all remote synchronization with Supabase.
        *   `OliveTreeImportService`/`SelahImportService`: Manages complex data ingestion from external sources (TSK, CSV).
    *   **`lib/database/`:** Data Access Layer (DAL). All database operations (local SQLite) should be performed through modules in this directory (`history_database.dart`, `highlights_database.dart`, etc.). **Do not access the underlying database connections directly from the UI or Service layers.**
    *   **`lib/utils/`:** Generic helper functions, constants, and platform detection logic (e.g., `internet_access_checker.dart`, `platform_paths.dart`).

*   **Native Targets:** Dedicated folders (`android/`, `ios/`, `windows/`, `linux/`, `macos/`) contain necessary platform-specific configuration and minimal code required to wrap the Flutter engine.

## 🧭 Code Patterns & Conventions

*   **State Management:** The application relies heavily on `ValueNotifier` for global application state (e.g., `themeModeNotifier`, `fontSizeNotifier`). Any modification to global UI state should involve updating a relevant `ValueNotifier`.
*   **Font Handling:** Fonts are managed globally via `lib/main.dart`. The application utilizes a comprehensive, hardcoded list of available fonts defined in `lib/main.dart:71-100`.
*   **Data Flow:** Data flows generally from external inputs (TSK imports, user actions) -> Service Layer (`lib/services/`) -> Data Access Layer (`lib/database/`) -> State/UI (`lib/screens/`).
*   **Data Persistence:** Data is managed using two primary mechanisms:
    1.  **Local SQLite:** Used for fast, offline data storage (managed via `sqflite`).
    2.  **Supabase:** Used for cloud synchronization and remote backup.

## 🛠️ Essential Commands & CI Context

*   **Testing:** The standard unit/widget testing command is `flutter test`.
*   **Dependencies:** Always run `flutter pub get` before attempting any build or test.
*   **CI/Build Gotcha (Version):** In CI environments (e.g., GitHub Actions), the application version is extracted specifically via:
    ```bash
    grep "final appVersion" lib/main.dart | sed 's/.*= "\(.*\)".*/\1/'
    ```
    This is a rigid pattern for version retrieval.
*   **Building:** Use platform-specific commands (e.g., `flutter build linux`, `flutter build web`) for final artifacts.

## ⚠️ Gotchas & Non-Obvious Knowledge

*   **Database Abstraction:** While SQLite is used locally, the application is designed to abstract database interaction through specialized files in `lib/database/`. Attempting to bypass these classes will lead to unstable code.
*   **Platform Dependency:** The application distinguishes between desktop and mobile/web environments (`_isDesktop`) and uses specific initialization logic for databases across these platforms (`sqflite_ffi`, `sqflite_ffi_web`).
*   **Data Export:** The application supports robust data export/import via a simple JSON format, allowing users to back up their data outside of the online sync service. Look for import logic in `lib/services/selah_import_service.dart`.