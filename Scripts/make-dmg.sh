#!/usr/bin/env bash
#
# Packages Vortexflow.app into a disk image for direct download.
#
# A DMG rather than a zip for one practical reason: it can carry a symlink to
# /Applications, so installing is a drag from one side of the window to the other.
# A zip lands the app in ~/Downloads, and an app run from there is a problem —
# macOS ties privacy permissions to a path, and the first tidy-up of the Downloads
# folder silently revokes everything VortexFlow was granted.
#
# Usage:
#   Scripts/make-dmg.sh                  # build, then package
#   Scripts/make-dmg.sh --skip-build     # package whatever is already in build/
#
# The image is signed with the same identity as the app when one exists.
# Notarization runs when credentials are present (VORTEXFLOW_NOTARY_PROFILE, or
# the App Store Connect API key triple). Scripts/notarize.sh submits the image
# and staples the ticket. Without credentials the image stays signed but not
# notarized, and Gatekeeper refuses a downloaded copy until the user approves it
# in System Settings.
#
# On macOS 15 and later the route is System Settings -> Privacy & Security ->
# Open Anyway, after an attempt to open has been refused. Control-clicking the
# app and choosing Open used to work and no longer does. Apple removed that
# bypass in Sequoia, which is at or below this app's minimum, so it is wrong for
# every supported version. The README has the current steps.
#
set -euo pipefail

SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--skip-build) SKIP_BUILD=1; shift ;;
		-h|--help) sed -n '2,27p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Vortexflow"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
	# Deliberately without --install: that installs to /Applications and then removes
	# the staging bundle, which is the very thing being packaged here.
	echo "==> Building the app"
	"$PROJECT_ROOT/Scripts/build-app.sh"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
	echo "error: $APP_BUNDLE does not exist; run without --skip-build" >&2
	exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
	"$APP_BUNDLE/Contents/Info.plist")"
VOLUME_NAME="$APP_NAME $VERSION"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
STAGING="$BUILD_DIR/dmg-staging"

echo "==> Staging $APP_NAME $VERSION"
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"

# What makes the drag-to-install gesture possible at all.
ln -s /Applications "$STAGING/Applications"

echo "==> Creating the disk image"
# UDZO is the compressed read-only format every macOS release can mount without
# extra software. -ov so a rebuild replaces the previous image rather than failing.
hdiutil create \
	-volname "$VOLUME_NAME" \
	-srcfolder "$STAGING" \
	-ov \
	-format UDZO \
	"$DMG_PATH" | sed 's/^/    /'

rm -rf "$STAGING"

# Sign the image with the same identity as the app when there is one. This does not
# satisfy Gatekeeper — only notarization does — but it does mean the download can be
# checked for tampering rather than being wholly unattributable.
SIGN_IDENTITY="${VORTEXFLOW_SIGN_IDENTITY:-}"
DEFAULT_IDENTITY_NAME="Vortexflow Dev"

if [[ -z "$SIGN_IDENTITY" ]]; then
	if security find-identity -p codesigning 2>/dev/null | grep -q "$DEFAULT_IDENTITY_NAME"; then
		SIGN_IDENTITY="$DEFAULT_IDENTITY_NAME"
	fi
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
	echo "==> Signing the image as \"$SIGN_IDENTITY\""
	codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH" 2>&1 | sed 's/^/    /'
fi

# NotaryCredentials = Profile | APIKey | Missing. Missing skips notarization
# rather than failing the packaging step. notarize.sh itself fails closed.
HAS_NOTARY_CREDENTIALS=0
if [[ -n "${VORTEXFLOW_NOTARY_PROFILE:-}" ]]; then
	HAS_NOTARY_CREDENTIALS=1
elif [[ -n "${APP_STORE_CONNECT_API_KEY_ID:-}" &&
	-n "${APP_STORE_CONNECT_ISSUER_ID:-}" &&
	-n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
	HAS_NOTARY_CREDENTIALS=1
fi

if [[ "$HAS_NOTARY_CREDENTIALS" -eq 1 ]]; then
	echo "==> Notarizing"
	"$PROJECT_ROOT/Scripts/notarize.sh" "$DMG_PATH"
fi

echo "==> Verifying"
# Mount it and check the app really is inside, because a DMG that builds cleanly and
# contains nothing useful looks identical from out here.
MOUNT_POINT="$(mktemp -d)"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null

if [[ -x "$MOUNT_POINT/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]]; then
	echo "    contains $APP_NAME.app"
	lipo -archs "$MOUNT_POINT/$APP_NAME.app/Contents/MacOS/$APP_NAME" |
		sed 's/^/    architectures: /'
	if codesign --verify --deep --strict "$MOUNT_POINT/$APP_NAME.app" 2>/dev/null; then
		echo "    app signature OK"
	else
		echo "    warning: the app inside the image failed signature verification" >&2
	fi
else
	echo "error: the image does not contain a runnable $APP_NAME.app" >&2
	hdiutil detach "$MOUNT_POINT" >/dev/null || true
	rmdir "$MOUNT_POINT"
	exit 1
fi

[[ -L "$MOUNT_POINT/Applications" ]] && echo "    contains the Applications shortcut"

hdiutil detach "$MOUNT_POINT" >/dev/null
rmdir "$MOUNT_POINT"

echo
echo "Built: ${DMG_PATH#$PROJECT_ROOT/}"
# The file's own size, not `du`, which reports allocated blocks and overstated this by a
# whole megabyte — the number quoted on a download page should be the number transferred.
stat -f %z "$DMG_PATH" | awk '{ printf "Size:   %.1f MB\n", $1 / 1048576 }'
shasum -a 256 "$DMG_PATH" | awk '{ print "SHA256: " $1 }'

if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
	echo "Stapled: ${DMG_PATH#$PROJECT_ROOT/}"
else
	cat <<-'NOTE'

	This image is signed but not notarized, so a downloaded copy is blocked on first
	open with "the developer cannot be verified". People have to try opening it once,
	then approve it in System Settings > Privacy & Security > Open Anyway. On macOS 15
	and later, Control-clicking and choosing Open no longer bypasses this.

	Notarizing instead, which removes the warning entirely, needs a paid Apple
	Developer account and notarytool credentials. See Scripts/notarize.sh.
NOTE
fi
