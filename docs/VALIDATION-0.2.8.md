# YA7 0.2.8 validation

- Build 10, Universal arm64/x86_64, Developer ID signed.
- 22 tests passed with English and 22 with German, zero failures.
- Locale catalogs, placeholder parity, English fallback, Finder bundle display names, About resources and project license resources tested.
- Native view renders inspected: settings in English/German, light/dark; compression dialog in both languages. No background version requests from the preview harness.
- Apple notarization Accepted, submission `ce2584de-ee34-4166-bba1-12ba141de6ed`, no findings; ticket stapled and validated. Gatekeeper accepts DMG and contained app.
- Read-only DMG payload matches signed export, icon preserved, localized resources in all four bundles, Applications link and license material verified.
- Direct Finder GUI and fresh installation on a second Mac were not available for this validation. Installed app was not replaced.
- Existing deprecation warning for NSItemProvider.loadItem remains; archive behavior is unchanged.
