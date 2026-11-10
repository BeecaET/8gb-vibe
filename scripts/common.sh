# Shared by package.sh and release.sh. Do not run directly.
# NAME: executable name (no spaces). DISPLAY_NAME: app name the user sees.
NAME="8GBVibe"
DISPLAY_NAME="8GB Vibe"
BUNDLE_ID="vn.beeca.8gbvibe"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
# Vietnamese is the development language; English comes from Resources/en.lproj/InfoPlist.strings.
COPYRIGHT="© 2026 BEECA. Source code licensed under Apache 2.0."  # English (development region); Vietnamese in Resources/vi.lproj/InfoPlist.strings

# MCP server for AI agents, shipped in Contents/Helpers.
MCP_NAME="8gbvibe-mcp"

# make_bundle <executable path> <.app path> [MCP helper path]
make_bundle() {
    local bin="$1" app="$2" helper="${3:-}"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$bin" "$app/Contents/MacOS/$NAME"
    if [ -n "$helper" ]; then
        mkdir -p "$app/Contents/Helpers"
        cp "$helper" "$app/Contents/Helpers/$MCP_NAME"
    fi
    cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
    cp Resources/BeecaLogo.png "$app/Contents/Resources/BeecaLogo.png"
    # Localizations: vi is the development language, en is English.
    cp -R Resources/*.lproj "$app/Contents/Resources/"
    # Emerald accent color (sidebar selection, switches, links). Users who picked their own accent in System Settings keep it.
    xcrun actool Resources/Assets.xcassets --compile "$app/Contents/Resources" --platform macosx \
        --minimum-deployment-target 13.0 --accent-color AccentColor \
        --output-partial-info-plist "$(mktemp -t actool).plist" >/dev/null
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSAccentColorName</key><string>AccentColor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>vi</string><string>en</string></array>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>$COPYRIGHT</string>
</dict>
</plist>
PLIST
}

# forget_bundle <.app path>: removes a build copy from LaunchServices so Spotlight and Launchpad
# show only the installed app (/Applications), not every build under build/.
forget_bundle() {
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$1" >/dev/null 2>&1 || true
}
