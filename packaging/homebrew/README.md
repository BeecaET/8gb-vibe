# Homebrew

`8gb-vibe.rb` is a template cask. It is not published yet: the tap `BeecaET/homebrew-tap` does not exist yet.

## Create the tap

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
