# mlController — Claude Code Project Notes

## Build System

- **Source of truth**: `project.yml` (XcodeGen) — always run `xcodegen generate` after modifying it and before committing
- **Build**: `make build` (universal binary: arm64 + x86_64)
- **Dev install**: `make install` (ad-hoc signed, installs to /Applications)
- **Release**: `make release` (sign → notarize → zip → appcast)

## Code Signing & Notarization

- **Signing identity**: `Developer ID Application: Boinx Software International GmbH (6372P8EH2J)`
- **Notarization keychain profile**: `mlController` (stored via `xcrun notarytool store-credentials`)
- **Team ID**: `6372P8EH2J`
- **Sparkle framework**: Requires inside-out codesigning (XPC services → Autoupdate → Updater.app → framework → app). Never use `--deep`.
- **Entitlements**: `mlController.entitlements` includes `com.apple.security.cs.disable-library-validation` for loading Sparkle framework in dev builds

## Sparkle Auto-Updates

- **Private key**: Stored in macOS Keychain (managed by Sparkle's `generate_keys` tool at `.build/artifacts/sparkle/Sparkle/bin/`)
- **Public key (SUPublicEDKey)**: Set in `project.yml` under info properties
- **Appcast URL**: `https://raw.githubusercontent.com/boinx/mlController/main/appcast.xml`
- **Release ZIP download URL pattern**: `https://github.com/boinx/mlController/releases/download/v{VERSION}/mlController-{VERSION}.zip`
- **Appcast generation**: `make appcast` copies ZIP to `releases/` and runs `generate_appcast`

## Release Workflow

1. Bump version in `project.yml` (both `CFBundleShortVersionString` and `CFBundleVersion`)
2. Run `xcodegen generate` to update Xcode project and Info.plist
3. `make release` — builds, signs with Developer ID, notarizes with Apple, creates ZIP, updates appcast.xml
4. Commit appcast.xml changes and push
5. Create GitHub release with `gh release create v{VERSION} mlController-{VERSION}.zip --title "..." --notes "..."`

## Conventions

- Run `xcodegen generate` before every commit that changes `project.yml`
- Web server (Swifter) binds to IPv6 (`::1`) — use `curl http://localhost:8990/` which tries IPv6 first
- Filesystem scans (`MimoLiveApp.findAll`, `LocalDocumentScanner`) run off the main thread to avoid blocking on iCloud-synced or TCC-protected directories
- Distribution format is ZIP (not DMG) — preserves code signatures and works with Sparkle

## GitHub

- **Repo**: `boinx/mlController`
- **Open issues**: Check with `gh issue list`
