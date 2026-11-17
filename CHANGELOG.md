# Changelog

## 0.2.10 — 2026-11-17

- Reserve a separate area for the 7-Zip update notice so it does not overlap the file browser; stack its link below the message at narrow widths.
- Apply context-menu actions to clicked files, including multiple files, rather than a previous selection.
- Read directories and metadata in the background; discard stale navigation results.
- Prepare sorted and filtered lists outside SwiftUI view construction, reuse sorting across searches, and cache selection statistics.
- Preserve English/German localization and add regression coverage for navigation, context actions, sorting, filtering and selection summaries (33 tests passing).

## 0.2.9 — 2026-10-30

- Fix Finder output handoff: stage archives and extracted folders in the system item replacement directory, as required by Apple's Action Extension example, so Finder can place the result after Done.
- Add a regression test that creates a real ZIP, extracts it, consumes both output providers and verifies original-file preservation. A user-assisted real Finder 7z creation test passed, including automated integrity and exact-content verification.

## 0.2.8 — 2026-10-30

- Add complete English and German interface resources; follow macOS language preferences with English fallback.
- Localize menus, dialog controls, accessibility labels, status/error messages, Finder action names and About text.
- Format file-list dates using the user's regional settings; preserve user file/archive names.
- Include YA7's LGPL license and licensing notice in the app and bilingual DMG instructions.
- Add localization coverage, placeholder, fallback and extension-resource tests; run all tests in both languages.

## 0.2.7 — 2026-10-30

- Add TAR, TAR.GZ, TAR.BZ2 and TAR.XZ creation with multi-file support.
- Add BZIP2, Zstandard, CAB, ISO and DMG recognition and compressed-TAR aliases.
- Browse and extract compressed TAR contents in a single operation.
- Share format definitions between the app and Finder actions.
- Add manual and optional weekly 7-Zip version checks while the app is running.
- Preserve successful version results on network failures and show update notices in the app.
- Pass 18 local Xcode tests; ship a Developer-ID-signed and Apple-notarized Universal DMG.

## Earlier local builds

Versions through 0.2.6 established the native archive UI, Finder Quick Actions, Zip Seven icon and notarization pipeline. They were local development releases.
