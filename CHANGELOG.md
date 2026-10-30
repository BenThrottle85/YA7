# Changelog

## 0.2.9 — 2026-10-30

- Fix Finder output handoff: stage archives and extracted folders in the system item replacement directory, as required by Apple's Action Extension example, so Finder can place the result after Done.
- Add a regression test that creates a real ZIP, extracts it, consumes both output providers and verifies original-file preservation. Direct Finder UI verification remains pending.

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
