#!/bin/bash
# Local test build: builds for this Mac's chip and signs ad hoc. Output: build/8GB Vibe.app
# No Xcode needed. -j 2 keeps the build light on an 8 GB Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

swift build -c release -j 2 --product "$NAME"
make_bundle "$(swift build -c release --show-bin-path)/$NAME" "build/$DISPLAY_NAME.app"
codesign --force --sign - "build/$DISPLAY_NAME.app"
echo "Done: build/$DISPLAY_NAME.app ($VERSION, build $BUILD_NUMBER)"
