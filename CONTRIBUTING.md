# Contributing to 8GB Vibe

English | [Tiếng Việt](#ghi-chú-tiếng-việt)

Thank you for helping. 8GB Vibe is a macOS menu bar app that keeps 8 GB Macs responsive while people vibe code. It is free and made by BEECA.

## Before you start

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

- Vietnamese is the development language. Translation keys are the Vietnamese sentences.
- Every new user-facing string needs an English line in `Resources/en.lproj/Localizable.strings`.
- SwiftUI `Text("...")` and `Button("...")` are localized automatically. For `String` values use `String(localized: "...", bundle: .main)`.
- Values in sentences use `%@` (strings, formatted numbers) and `%lld` (integers), for example `"Đã chọn %lld mục" = "%lld selected";`.
- Try English with `open -n "build/8GB Vibe.app" --args -AppleLanguages "(en)"`.

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

---

## Ghi chú tiếng Việt

- Báo lỗi: mở issue, ghi máy, RAM, phiên bản macOS. Tính năng mới: mở đề xuất trước khi viết code.
- Test lõi: `swift test -j 2`. Bản dùng thử: `./scripts/package.sh`. Không cần chạy `scripts/release.sh`.
- Code, tên tệp, chú thích, commit bằng tiếng Anh. Chuỗi giao diện: khoá là câu tiếng Việt, thêm bản tiếng Anh vào `Resources/en.lproj/Localizable.strings`.
- Chỉ dùng thư viện của Apple.
- Nguyên tắc an toàn bắt buộc: luôn hỏi trước, không tự tắt, không tự xoá, không gửi dữ liệu ra ngoài.
- Gửi PR nghĩa là đồng ý đóng góp theo Giấy phép Apache 2.0. Tên, icon 8GB Vibe và logo BEECA là nhãn hiệu, xem `TRADEMARKS.md`.
