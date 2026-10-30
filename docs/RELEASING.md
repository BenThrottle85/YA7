# Releasing YA7

## Repository setup (once)

Target: **BenThrottle85/YA7**, public. Create an empty repository without generated README/license/gitignore files, then push the reviewed local history to `main`. Do not force-push over an existing repository. Inspect an existing target before reusing it.

Repository description: `Native 7-Zip GUI for macOS with Finder Quick Actions.`
Suggested topics: `macos`, `swift`, `swiftui`, `7zip`, `archives`, `finder-extension`.

Enable Issues and GitHub private vulnerability reporting using the free public-repository features. GitHub Actions is limited to **standard `macos-26` and `macos-26-intel` runners in a public repository**, currently free under GitHub's public-repository billing rules. Every job has a `github.event.repository.private == false` guard. Do not use larger runners, artifact/cache uploads, paid security add-ons, Codespaces, paid hosting, Packages or other billable services. Never upgrade the GitHub plan or add billing on the user's behalf. See https://docs.github.com/en/billing/concepts/product-billing/github-actions.

After the initial free CI run succeeds, protect `main` with review and the two CI checks if these repository controls are available without a paid plan. Do not require nonexistent checks before the first successful run. No Apple signing credentials are needed by CI, and CI artifacts are not release/notarized builds.

The user requires **no paid Actions runs or other new costs**. If the repository becomes private, jobs must remain skipped. Reuse the existing Apple Developer membership and local identity; do not purchase or renew any service on the user's behalf.

## Release candidate

1. Update app/extension versions together, changelog and release notes. Build and test on an unlocked Mac; inspect Finder behavior, icon and output paths. Document outstanding checks.
2. Set local `YA7_SIGNING_IDENTITY`, `YA7_DEVELOPMENT_TEAM` and `YA7_NOTARY_PROFILE`. Store the actual Apple credentials only in Keychain. See [NOTARISIERUNG.md](../NOTARISIERUNG.md).
3. Build and notarize using explicit paths:

```sh
export YA7_BUILD_ROOT="$PWD/.build/release"
export YA7_WORK_ROOT="$PWD/.build/notary"
sh build-app.sh "$PWD/dist/YA7.app"
sh Scripts/notarize.sh "$PWD/dist/YA7.app" "$PWD/dist/YA7-0.2.7-macOS.dmg"
```

4. Require Apple `Accepted`, inspect the notary log, validate the attached ticket, assess both image and contained app with Gatekeeper, and compare the mounted app with the verified export. Compute SHA-256 **after** stapling. Never modify/re-sign the final app or DMG after these checks.
5. Attach the notarized DMG, its checksum, the exact matching source archive, `LICENSE`, `LICENSING.md` and third-party notices to the GitHub Release. Include vendor source and original license texts in the source archive. The 0.2.7 app predates the root YA7 licensing documents; ship the accompanying license notices with that release. The repository license grant explicitly covers the project-owned code in that binary.
6. Keep the first release as a **pre-release** until the documented fresh-Mac/Finder/Intel checks are complete. Source availability and notarization do not certify these unperformed tests.

## First publication

The prepared local release directory is outside the repository, under `outputs/YA7-GitHub-Release-0.2.7` in the maintainer workspace. It is not committed. Review the files and use its release notes for a **draft** GitHub Release tagged `v0.2.7`, targeting the reviewed publication commit. Upload the matching assets before publishing. Do not tag the original initialization commit: it predates the public licensing and documentation.

No workflow auto-publishes a release, imports certificates or installs a build. Do not upload private Apple keys, `.env` files, workspace logs, personal paths or raw local test reports as release assets.
