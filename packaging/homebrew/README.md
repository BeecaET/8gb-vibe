# Homebrew

`8gb-vibe.rb` is a template cask. It is not published yet. The tap is created only when the repository goes public (after roadmap step 3, see `docs/CHUC_NANG.md` section 3).

## Create the tap (when going public)

1. Create a public repository named `BeecaET/homebrew-tap`. Homebrew needs the `homebrew-` prefix.
2. Put the cask at `Casks/8gb-vibe.rb` in that repository.
3. Users install with:

```bash
brew install --cask beecaet/tap/8gb-vibe
```

## Each release

1. Upload the notarized DMG to `https://8gb.beeca.vn/tai-ve/8GB-Vibe-<version>.dmg`.
2. Compute the checksum (also in the `.sha256` file next to the DMG):

```bash
shasum -a 256 build/release/8GB-Vibe-<version>.dmg
```

3. In the tap, update `version` and `sha256`, then check the cask:

```bash
brew audit --cask --online beecaet/tap/8gb-vibe
```

```bash
brew install --cask beecaet/tap/8gb-vibe
```

Only notarized DMGs go into the cask. The URL must serve the exact file whose checksum is in the cask.

## Ghi chú tiếng Việt

- Tệp `8gb-vibe.rb` là mẫu, chưa phát hành. Chỉ tạo repo tap `BeecaET/homebrew-tap` (công khai) khi chuyển repo 8GB Vibe sang công khai.
- Mỗi bản phát hành: tải DMG đã notarize lên `8gb.beeca.vn/tai-ve/`, cập nhật `version` và `sha256` trong cask, chạy `brew audit`.
