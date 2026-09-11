#!/usr/bin/env bash
#
# Builds the app and menu-bar icons from the website brand pack in site/img/brand.
#
# The site is the source of truth. This script only rasterises and packages, so a
# brand change there becomes a brand change in the app by re-running:
#
#   Scripts/generate-icons.sh
#
# Requires the Command Line Tools (sips, iconutil, swift). No extra packages.
#
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRAND_PNG="$PROJECT_ROOT/site/img/brand/png"
APP_RESOURCES="$PROJECT_ROOT/Resources"
CORE_RESOURCES="$PROJECT_ROOT/Sources/VortexflowCore/Resources"

APP_ICON_SOURCE="$BRAND_PNG/app-icon-1024.png"
MARK_SOURCE="$BRAND_PNG/vortexflow-mark-1024.png"

for required in "$APP_ICON_SOURCE" "$MARK_SOURCE"; do
	if [[ ! -f "$required" ]]; then
		echo "error: missing brand asset: ${required#$PROJECT_ROOT/}" >&2
		exit 1
	fi
done

mkdir -p "$APP_RESOURCES" "$CORE_RESOURCES"

# Package the approved image masters for the site. SVG URLs remain available as
# self-contained image wrappers, not a second hand-maintained logo drawing.
swift -module-cache-path "$PROJECT_ROOT/.build/brand-module-cache" \
  "$PROJECT_ROOT/Scripts/export-brand.swift" "$PROJECT_ROOT"

# --- App icon (.icns) -------------------------------------------------------
# Finder, System Settings privacy lists, Activity Monitor and the DMG all read
# CFBundleIconFile. The 1024 px plate from the brand pack is the app icon; the
# sizes below are the iconset Apple still expects of a command-line-built bundle.

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"

resize_icon() {
	local pixels="$1"
	local name="$2"
	sips -z "$pixels" "$pixels" "$APP_ICON_SOURCE" --out "$ICONSET/$name" >/dev/null
}

resize_icon 16   icon_16x16.png
resize_icon 32   icon_16x16@2x.png
resize_icon 32   icon_32x32.png
resize_icon 64   icon_32x32@2x.png
resize_icon 128  icon_128x128.png
resize_icon 256  icon_128x128@2x.png
resize_icon 256  icon_256x256.png
resize_icon 512  icon_256x256@2x.png
resize_icon 512  icon_512x512.png
cp "$APP_ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$APP_RESOURCES/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"
echo "    Resources/AppIcon.icns"

# --- Colour mark (windows and menu bar) -------------------------------------
# The three-colour spiral without the dark squircle. Finder still uses the plated
# app icon above; in-app chrome sits on its own background and does not want a
# second white plate. Quick Look paints SVG thumbnails on white, so this is
# drawn through AppKit onto a clear bitmap instead of qlmanage.

rasterize_mark() {
	local svg="$1"
	local png="$2"
	local pixels="$3"
	swift -module-cache-path "$PROJECT_ROOT/.build/brand-module-cache" - "$svg" "$png" "$pixels" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count >= 4,
      let pixels = Int(CommandLine.arguments[3]), pixels > 0 else {
    fputs("usage: rasterize <svg> <png> <pixels>\n", stderr)
    exit(2)
}

let svgURL = URL(fileURLWithPath: CommandLine.arguments[1])
let pngURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: svgURL), image.isValid else {
    fputs("error: could not load \(svgURL.path)\n", stderr)
    exit(1)
}

let size = NSSize(width: pixels, height: pixels)
guard let representation = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("error: could not create bitmap\n", stderr)
    exit(1)
}
representation.size = size

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
    fputs("error: could not create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
image.draw(
    in: NSRect(origin: .zero, size: size),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

guard let data = representation.representation(using: .png, properties: [:]) else {
    fputs("error: could not encode PNG\n", stderr)
    exit(1)
}
do {
    try data.write(to: pngURL)
} catch {
    fputs("error: could not write \(pngURL.path): \(error)\n", stderr)
    exit(1)
}
SWIFT
}

MARK_MASTER="$(mktemp -t vortexflow-mark).png"
rasterize_mark "$MARK_SOURCE" "$MARK_MASTER" 1024

sips -z 256 256 "$MARK_MASTER" --out "$CORE_RESOURCES/VortexflowMark.png" >/dev/null
echo "    Sources/VortexflowCore/Resources/VortexflowMark.png"

# Full colour, not a template: flattening to menu-bar ink would throw away the
# three spiral colours that *are* the logo. Status items are 18 pt.

sips -z 18 18 "$MARK_MASTER" --out "$CORE_RESOURCES/MenuBarMark.png" >/dev/null
sips -z 36 36 "$MARK_MASTER" --out "$CORE_RESOURCES/MenuBarMark@2x.png" >/dev/null
sips -z 54 54 "$MARK_MASTER" --out "$CORE_RESOURCES/MenuBarMark@3x.png" >/dev/null
cp "$CORE_RESOURCES/MenuBarMark.png" "$BRAND_PNG/menu-bar-18.png"
cp "$CORE_RESOURCES/MenuBarMark@2x.png" "$BRAND_PNG/menu-bar-36.png"
cp "$CORE_RESOURCES/MenuBarMark@3x.png" "$BRAND_PNG/menu-bar-54.png"
echo "    Sources/VortexflowCore/Resources/MenuBarMark.png (+ @2x, @3x)"

rm -f "$MARK_MASTER"

echo
echo "Icons generated from site/img/brand. Re-run after a brand change."
