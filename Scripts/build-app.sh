#!/usr/bin/env bash
#
# Builds Vortexflow.app from the SwiftPM package.
#
# SwiftPM produces a bare executable; macOS needs a bundle. This script assembles
# one, because the bundle is not cosmetic here:
#
#   * TCC (Accessibility / Screen Recording / Input Monitoring) attaches grants to a
#     bundle identity. A loose executable gets re-prompted or silently denied.
#   * LSUIElement lives in Info.plist, and it is what keeps VortexFlow out of the
#     Dock and out of Cmd-Tab.
#   * NSStatusItem and the non-activating panel both want a real bundled app.
#
# Usage:
#   Scripts/build-app.sh                 # release, universal if possible
#   Scripts/build-app.sh --install       # also replace /Applications/Vortexflow.app
#   Scripts/build-app.sh --debug         # debug configuration
#   Scripts/build-app.sh --native-arch   # skip the universal build
#
# Brand icons are generated from site/img/brand by Scripts/generate-icons.sh
# and copied into the bundle here. Re-run that script after a brand change.
#
# Signing:
#   Run Scripts/create-signing-certificate.sh once. Without a stable signing
#   identity, macOS forgets VortexFlow's permissions on every rebuild and can end up
#   refusing to add it to the privacy lists at all.
#
set -euo pipefail

CONFIGURATION="release"
UNIVERSAL=1
INSTALL=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--debug) CONFIGURATION="debug"; shift ;;
		--release) CONFIGURATION="release"; shift ;;
		--native-arch) UNIVERSAL=0; shift ;;
		--install) INSTALL=1; shift ;;
		-h|--help) sed -n '2,25p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Vortexflow"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

echo "==> Building $APP_NAME ($CONFIGURATION)"

BUILD_ARGS=(--configuration "$CONFIGURATION")
BUILT_BINARY=""

if [[ "$UNIVERSAL" -eq 1 ]]; then
	# A universal binary needs both slices. Intel Macs are still in the support
	# matrix, and an Apple-Silicon-only build would silently exclude them.
	echo "==> Attempting universal build (arm64 + x86_64)"
	if swift build "${BUILD_ARGS[@]}" --arch arm64 --arch x86_64 2>/dev/null; then
		echo "    universal build succeeded"
	else
		echo "    universal build unavailable with this toolchain; falling back to the native architecture"
		UNIVERSAL=0
		swift build "${BUILD_ARGS[@]}"
	fi
else
	swift build "${BUILD_ARGS[@]}"
fi

# Locate the product. The path differs between build systems and between
# single-arch and universal builds, so ask SwiftPM first and search only if that
# comes up empty.
locate_binary() {
	local bin_path
	if bin_path="$(swift build "${BUILD_ARGS[@]}" --show-bin-path 2>/dev/null)"; then
		if [[ -f "$bin_path/$APP_NAME" ]]; then
			echo "$bin_path/$APP_NAME"
			return 0
		fi
	fi
	# Fall back to searching, newest first, excluding intermediates.
	find "$PROJECT_ROOT/.build" -type f -name "$APP_NAME" -perm +111 \
		! -path "*Intermediates.noindex*" ! -path "*.dSYM*" 2>/dev/null |
		while read -r candidate; do
			if file "$candidate" | grep -q "Mach-O.*executable"; then
				echo "$candidate"
				return 0
			fi
		done
	return 1
}

BUILT_BINARY="$(locate_binary || true)"
if [[ -z "$BUILT_BINARY" || ! -f "$BUILT_BINARY" ]]; then
	echo "error: could not locate the built $APP_NAME executable" >&2
	exit 1
fi
echo "==> Built executable: ${BUILT_BINARY#$PROJECT_ROOT/}"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BUILT_BINARY" "$CONTENTS/MacOS/$APP_NAME"
chmod +x "$CONTENTS/MacOS/$APP_NAME"
cp "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Finder, System Settings and the status item all read these from the app
# bundle. SwiftPM's resource bundle is left behind in .build when only the
# executable is copied, so the same files also go in Contents/Resources.
if [[ -f "$PROJECT_ROOT/Resources/AppIcon.icns" ]]; then
	cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
else
	echo "    warning: Resources/AppIcon.icns is missing; run Scripts/generate-icons.sh" >&2
fi
CORE_BRAND="$PROJECT_ROOT/Sources/VortexflowCore/Resources"
if compgen -G "$CORE_BRAND/*.png" >/dev/null; then
	cp "$CORE_BRAND"/*.png "$CONTENTS/Resources/"
fi

echo "==> Embedding Sparkle.framework"
locate_sparkle_framework() {
	local bin_path candidate
	local -a candidates=()

	candidates+=(
		"$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
	)
	if bin_path="$(swift build "${BUILD_ARGS[@]}" --show-bin-path 2>/dev/null)"; then
		candidates+=(
			"$bin_path/Sparkle.framework"
			"$bin_path/../Sparkle.framework"
		)
	fi
	while IFS= read -r candidate; do
		candidates+=("$candidate")
	done < <(
		find "$PROJECT_ROOT/.build" -type d -name Sparkle.framework \
			! -path "*Intermediates.noindex*" 2>/dev/null | head -20 || true
	)
	for candidate in "${candidates[@]}"; do
		if [[ -d "$candidate" && -f "$candidate/Sparkle" || -d "$candidate/Versions" ]]; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

SPARKLE_FRAMEWORK="$(locate_sparkle_framework || true)"
if [[ -z "$SPARKLE_FRAMEWORK" || ! -d "$SPARKLE_FRAMEWORK" ]]; then
	echo "error: could not locate Sparkle.framework after swift build" >&2
	exit 1
fi
echo "    from ${SPARKLE_FRAMEWORK#$PROJECT_ROOT/}"
mkdir -p "$CONTENTS/Frameworks"
# Preserve symlinks. A flattened copy breaks the versioned framework layout.
ditto "$SPARKLE_FRAMEWORK" "$CONTENTS/Frameworks/Sparkle.framework"

# Signing identity.
#
# macOS records privacy permissions against a code identity. An ad-hoc signature
# (`--sign -`) produces a *different* identity on every build, which means grants are
# lost on each rebuild and stale records accumulate under the same bundle identifier
# until macOS refuses to add the app to the privacy lists at all — the "+" button
# stops doing anything.
#
# So prefer a real signing identity. Resolution order:
#   1. $VORTEXFLOW_SIGN_IDENTITY, if set
#   2. a certificate named "Vortexflow Dev" (Scripts/create-signing-certificate.sh)
#   3. ad-hoc, with a warning
#
# Signing mode is a sum type, chosen from the resolved identity:
#   * Developer ID Application: hardened runtime (--options runtime) and Apple
#     timestamp. Required for notarization.
#   * Vortexflow Dev or ad-hoc: --timestamp=none, no hardened runtime. Sparkle
#     fails to load under library validation when the signature is local or ad-hoc.
SIGN_IDENTITY="${VORTEXFLOW_SIGN_IDENTITY:-}"
DEFAULT_IDENTITY_NAME="Vortexflow Dev"

if [[ -z "$SIGN_IDENTITY" ]]; then
	# No -v: a self-signed certificate reports as untrusted and `-v` hides it, but
	# codesign signs with it fine. Trust matters for verifying, not for signing.
	if security find-identity -p codesigning 2>/dev/null | grep -q "$DEFAULT_IDENTITY_NAME"; then
		SIGN_IDENTITY="$DEFAULT_IDENTITY_NAME"
	else
		SIGN_IDENTITY="-"
	fi
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
	echo "==> Code signing (ad-hoc)"
else
	echo "==> Code signing as \"$SIGN_IDENTITY\""
fi

# SigningMode = DeveloperID | Local
codesign_item() {
	local target="$1"
	shift
	if [[ "$SIGN_IDENTITY" == "Developer ID Application"* ]]; then
		codesign --force --sign "$SIGN_IDENTITY" \
			--options runtime \
			--timestamp \
			--generate-entitlement-der \
			"$@" \
			"$target"
	else
		codesign --force --sign "$SIGN_IDENTITY" \
			--timestamp=none \
			"$@" \
			"$target"
	fi
}

sign_sparkle_inside_out() {
	local framework="$CONTENTS/Frameworks/Sparkle.framework"
	local version_dir="$framework/Versions/B"
	if [[ ! -d "$version_dir" ]]; then
		version_dir="$framework/Versions/Current"
	fi
	if [[ ! -d "$version_dir" ]]; then
		version_dir="$framework"
	fi

	local nested
	for nested in \
		"$version_dir/XPCServices/Downloader.xpc" \
		"$version_dir/XPCServices/Installer.xpc" \
		"$version_dir/Autoupdate" \
		"$version_dir/Updater.app"
	do
		if [[ -e "$nested" ]]; then
			echo "    signing ${nested#$CONTENTS/}"
			codesign_item "$nested" --preserve-metadata=entitlements,identifier
		fi
	done

	echo "    signing Frameworks/Sparkle.framework"
	codesign_item "$framework" --preserve-metadata=entitlements,identifier
}

sign_sparkle_inside_out 2>&1 | sed 's/^/    /'

echo "    signing $APP_NAME.app"
codesign_item "$APP_BUNDLE" \
	--entitlements "$PROJECT_ROOT/Resources/Vortexflow.entitlements" \
	2>&1 | sed 's/^/    /'

echo "==> Verifying"
if codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
	echo "    signature OK"
else
	echo "    warning: signature verification reported a problem" >&2
fi

# The designated requirement is what macOS matches privacy grants against. With a
# certificate it names the cert, so it survives rebuilds. Ad-hoc pins the exact
# binary hash instead, which is why ad-hoc builds keep losing their permissions.
echo "    designated requirement:"
codesign -d -r- "$APP_BUNDLE" 2>/dev/null | sed 's/^designated => /      /' | tail -1

ARCHS="$(lipo -archs "$CONTENTS/MacOS/$APP_NAME" 2>/dev/null || echo "unknown")"
echo "    architectures: $ARCHS"
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$CONTENTS/Info.plist" |
	sed 's/^/    bundle id: /'
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$CONTENTS/Info.plist" |
	sed 's/^/    LSUIElement: /'
if [[ -f "$CONTENTS/Resources/AppIcon.icns" ]]; then
	echo "    app icon: AppIcon.icns"
else
	echo "    warning: app icon missing from the bundle" >&2
fi

echo
echo "Built: ${APP_BUNDLE#$PROJECT_ROOT/}"

if [[ "$INSTALL" -eq 1 ]]; then
	echo
	echo "==> Installing to /Applications"
	# Quit any running copy first: replacing a running bundle leaves the old process
	# attached to a bundle that no longer exists, and macOS keeps the stale identity.
	if pgrep -f "/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
		echo "    quitting the running copy"
		pkill -f "/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME" || true
		sleep 1
	fi
	rm -rf "/Applications/$APP_NAME.app"
	cp -R "$APP_BUNDLE" /Applications/
	echo "    installed at /Applications/$APP_NAME.app"
	INSTALLED_PATH="/Applications/$APP_NAME.app"

	# Remove the staging copy once it has been installed. Leaving it behind gave Spotlight two
	# identical "VortexFlow" results with no way to tell which was which, and the wrong one is a
	# trap: build/ is deleted on the next build, so a privacy grant given to it points at a path
	# that no longer exists. Without --install the bundle stays put, since then it is the product.
	rm -rf "$APP_BUNDLE"
else
	INSTALLED_PATH="$APP_BUNDLE"
fi

echo
if [[ "$SIGN_IDENTITY" == "-" ]]; then
	cat <<-'WARNING'
	NOTE: this build is ad-hoc signed, so its code identity changes every time you
	rebuild. macOS ties privacy permissions to that identity, which means:

	  * permissions have to be granted again after each rebuild, and
	  * stale records build up until macOS stops adding the app to the privacy
	    lists entirely (the "+" button appears to do nothing)

	Fix it once:

	    Scripts/create-signing-certificate.sh
	    tccutil reset All io.vortexflow.Vortexflow
	    Scripts/build-app.sh --install

	WARNING
fi

echo "Run it with:  open '$INSTALLED_PATH'"
echo "Check setup:  '$INSTALLED_PATH/Contents/MacOS/$APP_NAME' --probe"
echo
echo "VortexFlow will ask for Input Monitoring, Accessibility and Screen Recording."
echo "Grant all three for the full experience; it degrades gracefully without each."
