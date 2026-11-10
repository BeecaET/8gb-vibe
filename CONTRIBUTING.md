# Contributing to 8GB Vibe


Thank you for helping. 8GB Vibe is a macOS menu bar app that keeps 8 GB Macs responsive while people vibe code. It is free and made by BEECA.

## Before you start

- Issues and pull requests are welcome in English or Vietnamese. A Vietnamese overview of the app is in [README.vi.md](README.vi.md).
- For a bug, open an issue with your Mac model, RAM and macOS version.
- For a new feature, open a feature request first so we can agree on the idea before you write code.
- Security problems: do not open a public issue, see [SECURITY.md](SECURITY.md).

## Build and test

You need macOS 13 or later and the Swift toolchain (Xcode or the Command Line Tools). No third-party packages.

Run the core tests:

```bash
swift test -j 2
```

Build a local test app (ad hoc signed, for this Mac's chip only):

```bash
./scripts/package.sh
```

```bash
open "build/8GB Vibe.app"
```

`-j 2` keeps the build light on an 8 GB Mac. Release builds (`scripts/release.sh`) need BEECA's Developer ID and notarization profile, so contributors do not run them. CI runs `swift build` and `swift test` on every pull request.

## Code conventions

- Code, file names, comments and commit messages in English. Keep commits small and focused.
- `Sources/VibeCore` has no UI and should be covered by tests in `Tests/VibeCoreTests`. UI goes in `Sources/EightGBVibe`.
- Only Apple frameworks. Do not add third-party dependencies.
- Keep the app light: under 50 MB of RAM and close to 0 % CPU in the background.

## UI text: Vietnamese and English

- English is the development language. Translation keys are the English sentences written in the code; no Vietnamese text goes in `Sources/`.
- Every new user-facing string needs a Vietnamese line in `Resources/vi.lproj/Localizable.strings`. `en.lproj` needs no entries.
- SwiftUI `Text("...")` and `Button("...")` are localized automatically. For `String` values use `String(localized: "...", bundle: .main)`.
- Values in sentences use `%@` (strings, formatted numbers) and `%lld` (integers), for example `"%lld selected" = "Đã chọn %lld mục";`. When the Vietnamese order differs, use positional specifiers (`%1$@`, `%2$@`).
- Check with `scripts/check-l10n.sh` (every key in the code has a Vietnamese entry) and `swift test` (no Vietnamese text in `Sources/`).
- Stored names (UserDefaults keys, file names, JSON keys) keep their old Vietnamese values; see `StoredName`. Never rename them.
- Try Vietnamese with `open -n "build/8GB Vibe.app" --args -AppleLanguages "(vi)"`.

## Safety rules (must keep)

These are part of the product. Pull requests that break them will not be merged.

1. **Always ask first.** Every quit, stop or clean-up is chosen and confirmed by the user.
2. **Never quit on its own.** No automatic quitting, killing or stopping of apps, sessions or servers.
3. **Never delete on its own.** Anything that removes files goes through a confirmation and, where possible, the Trash.
4. Never quit the app itself, Finder, Dock, macOS system processes or the Claude app.
5. Send no data off the Mac by default. Do not read the Keychain or browser cookies. Do not open an HTTP server. Do not disable macOS services or call `purge`.
6. Log every action the user confirms.

## Pull requests

- Describe what changed and why, and how you tested it (Mac model and RAM help).
- Add or update tests for core changes.
- Add screenshots for UI changes, in Vietnamese and English if you can.
- By sending a pull request you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), as stated in section 5 of the License.
- The 8GB Vibe name, icon and the BEECA logo are trademarks, see [TRADEMARKS.md](TRADEMARKS.md).
