# Contributing

Open an issue before a large behavioral change. For fixes, include a minimal reproduction, macOS version, YA7 version, archive format and expected/actual behavior. Remove personal data from examples and logs.

Build with Xcode and run the YA7 app-host tests in an unlocked Mac session. Preserve existing files, path/link checks, cancellation cleanup and stdin-only password handling. Archive/update-check tests must not depend on live network access. Keep main-app and Finder format recognition aligned through `ArchiveFormat` and the project generator.

Submit focused pull requests describing behavior and verification. Do not commit certificates, private keys, passwords, profiles, `.env` files, app exports, build products or personal logs. New fixtures should be small, reproducible and carry clear provenance/licensing. Contributions to project-owned files use LGPL-2.1-or-later; preserve separate third-party terms. Use synthetic archives, not confidential user data.

See [.github/SECURITY.md](.github/SECURITY.md) before reporting a suspected vulnerability.
