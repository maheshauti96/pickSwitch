#!/usr/bin/env bash
# Build a separate debug-only native rendering fixture. Never installs the app.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
swift build --configuration debug
BIN_DIR="$(swift build --configuration debug --show-bin-path)"
PREVIEW="$PROJECT_ROOT/build/VortexflowVisualPreview.app"
if [[ -e "$PREVIEW" ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PREVIEW/Contents/Info.plist")" == io.vortexflow.VisualPreview ]] || exit 1
fi
mkdir -p "$PREVIEW/Contents/MacOS" "$PREVIEW/Contents/Resources"
cp "$BIN_DIR/Vortexflow" "$PREVIEW/Contents/MacOS/Vortexflow"
cp Resources/Info.plist "$PREVIEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.vortexflow.VisualPreview' "$PREVIEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName VortexFlow Visual Preview' "$PREVIEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName VortexFlow Visual Preview' "$PREVIEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "$PREVIEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :VortexflowVisualPreview bool true' "$PREVIEW/Contents/Info.plist"
mkdir -p "$PREVIEW/Contents/Resources/PreviewIcons"
cp site/img/logos/*.png "$PREVIEW/Contents/Resources/PreviewIcons/"
cp Resources/AppIcon.icns "$PREVIEW/Contents/Resources/"
cp Sources/VortexflowCore/Resources/*.png "$PREVIEW/Contents/Resources/"
codesign --force --sign - --timestamp=none "$PREVIEW"
echo "Native visual preview built: $PREVIEW"
