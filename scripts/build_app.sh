#!/bin/bash
# Builds "Wafflez Wordz.app" into ./build. Needs macOS 14+ and Xcode (or the Command Line Tools).
#   ./scripts/build_app.sh            build a release app
#   ./scripts/build_app.sh --install  build, then copy to /Applications
# Optional: SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" to sign with a stable identity
# (keeps the Accessibility permission across rebuilds). Defaults to ad-hoc signing.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Wafflez Wordz is a Mac app — run this on macOS." >&2
  exit 1
fi

echo "▸ Building…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Wafflez Wordz.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WafflezWordz" "$APP/Contents/MacOS/WafflezWordz"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Copy any SwiftPM resource bundles next to the executable.
find "$BIN_DIR" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

echo "▸ Signing (${SIGN_IDENTITY:-ad-hoc})…"
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"

echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x WafflezWordz 2>/dev/null || true
  rm -rf "/Applications/Wafflez Wordz.app"
  cp -R "$APP" /Applications/
  echo "✓ Installed to /Applications/Wafflez Wordz.app"
  open "/Applications/Wafflez Wordz.app"
fi
