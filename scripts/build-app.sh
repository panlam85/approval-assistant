#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PACKAGE_ROOT=${SCRIPT_DIR:h}
APP_NAME="Approval Assistant"
EXECUTABLE_NAME="ApprovalAssistant"
APP_BUNDLE="$PACKAGE_ROOT/build/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"

swift build \
  --package-path "$PACKAGE_ROOT" \
  --configuration release

BIN_DIR=$(swift build \
  --package-path "$PACKAGE_ROOT" \
  --configuration release \
  --show-bin-path)

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS_DIR/MacOS"
cp "$PACKAGE_ROOT/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
chmod 755 "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"

plutil -lint "$CONTENTS_DIR/Info.plist"
codesign --force --sign - "$APP_BUNDLE"

echo "$APP_BUNDLE"
