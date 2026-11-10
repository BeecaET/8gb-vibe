#!/bin/bash
# Local test build: builds for this Mac's chip and signs ad hoc. Output: build/8GB Vibe.app
# No Xcode needed. -j 2 keeps the build light on an 8 GB Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

swift build -c release -j 2 --product "$NAME"
swift build -c release -j 2 --product "$MCP_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"
make_bundle "$BIN_DIR/$NAME" "build/$DISPLAY_NAME.app" "$BIN_DIR/$MCP_NAME"
codesign --force --sign - "build/$DISPLAY_NAME.app/Contents/Helpers/$MCP_NAME"
codesign --force --sign - "build/$DISPLAY_NAME.app"
forget_bundle "build/$DISPLAY_NAME.app"
echo "Done: build/$DISPLAY_NAME.app ($VERSION, build $BUILD_NUMBER)"
