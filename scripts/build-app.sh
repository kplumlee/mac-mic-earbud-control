#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="BTMicRouter.app"
BUNDLE_ID="com.kplumlee.btmicrouter"
EXECUTABLE="btmicrouter"
BINARY=".build/release/${EXECUTABLE}"

echo "==> Building ${EXECUTABLE} (release)..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release

echo "==> Assembling ${APP_NAME}..."
rm -rf "${APP_NAME}"
mkdir -p "${APP_NAME}/Contents/MacOS"

cp "${BINARY}" "${APP_NAME}/Contents/MacOS/${EXECUTABLE}"

cat > "${APP_NAME}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>BTMicRouter</string>
    <key>CFBundleDisplayName</key>
    <string>Bluetooth Mic Router</string>
    <key>CFBundleIdentifier</key>
    <string>com.kplumlee.btmicrouter</string>
    <key>CFBundleExecutable</key>
    <string>btmicrouter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Code signing (ad-hoc)..."
echo "    NOTE: Using ad-hoc signing (-). The app will run on this Mac but"
echo "    cannot be distributed to other machines without a Developer ID certificate."
codesign --force --deep --sign - "${APP_NAME}"

echo ""
echo "==> Done: ${PWD}/${APP_NAME}"
echo "    Move to ~/Applications to make it permanent:"
echo "      mv ${APP_NAME} ~/Applications/"
echo "    Then open it — it will appear in the menu bar (no Dock icon)."
