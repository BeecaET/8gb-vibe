# Template cask for the future tap BeecaET/homebrew-tap.
# Copy to Casks/8gb-vibe.rb in the tap. Update version and sha256 for each release:
#   shasum -a 256 build/release/8GB-Vibe-<version>.dmg
cask "8gb-vibe" do
  version "1.0.0"
  sha256 "5cca419f5dc0c572ccd165832868bb3869c00d941ed0b1009f95651ea634e744"

  url "https://8gb.beeca.vn/tai-ve/8GB-Vibe-#{version}.dmg"
  name "8GB Vibe"
  desc "Menu bar app that keeps 8 GB Macs responsive while vibe coding"
  homepage "https://8gb.beeca.vn/"

  depends_on macos: ">= :ventura"

  app "8GB Vibe.app"

  uninstall quit: "vn.beeca.8gbvibe"

  zap trash: [
    "~/Library/Application Support/8GB Vibe",
    "~/Library/Preferences/vn.beeca.8gbvibe.plist",
  ]
end
