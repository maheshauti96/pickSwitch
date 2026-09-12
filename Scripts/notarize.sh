#!/usr/bin/env bash
#
# Submits a disk image to Apple's notary service and staples the ticket.
#
# Usage:
#   Scripts/notarize.sh path/to/Something.dmg
#
# Credentials are a sum type, parsed here at the script boundary:
#
#   * keychain profile: VORTEXFLOW_NOTARY_PROFILE
#   * or App Store Connect API key triple:
#       APP_STORE_CONNECT_API_KEY_ID
#       APP_STORE_CONNECT_ISSUER_ID
#       APP_STORE_CONNECT_API_KEY_PATH
#   * or missing, which is a hard fail
#
# A paid Apple Developer account is required. Store a profile once with
# `xcrun notarytool store-credentials`, or point the API key env vars at a .p8.
#
# Already-stapled images exit 0 without talking to Apple.
#
set -euo pipefail

usage() {
	sed -n '2,21p' "$0"
}

if [[ $# -eq 0 ]]; then
	usage >&2
	exit 2
fi

case "$1" in
	-h|--help)
		usage
		exit 0
		;;
esac

if [[ $# -ne 1 ]]; then
	echo "usage: Scripts/notarize.sh path/to/Something.dmg" >&2
	exit 2
fi

DMG_PATH="$1"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# NotaryCredentials = Profile | APIKey | Missing
NOTARY_KIND="missing"
if [[ -n "${VORTEXFLOW_NOTARY_PROFILE:-}" ]]; then
	NOTARY_KIND="profile"
elif [[ -n "${APP_STORE_CONNECT_API_KEY_ID:-}" &&
	-n "${APP_STORE_CONNECT_ISSUER_ID:-}" &&
	-n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]]; then
	NOTARY_KIND="api-key"
fi

if [[ -f "$DMG_PATH" ]] && xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
	echo "Already stapled: $DMG_PATH"
	exit 0
fi

if [[ "$NOTARY_KIND" == "missing" ]]; then
	cat >&2 <<'EOF'
error: notarization needs a paid Apple Developer account and credentials.

Store a notarytool profile once:

    xcrun notarytool store-credentials

Then set VORTEXFLOW_NOTARY_PROFILE to that profile name. Or set the App Store
Connect API key triple:

    APP_STORE_CONNECT_API_KEY_ID
    APP_STORE_CONNECT_ISSUER_ID
    APP_STORE_CONNECT_API_KEY_PATH
EOF
	exit 2
fi

if [[ ! -f "$DMG_PATH" ]]; then
	echo "error: not a file: $DMG_PATH" >&2
	exit 1
fi

echo "==> Submitting ${DMG_PATH#$PROJECT_ROOT/} to Apple's notary service"

case "$NOTARY_KIND" in
	profile)
		xcrun notarytool submit "$DMG_PATH" --wait \
			--keychain-profile "$VORTEXFLOW_NOTARY_PROFILE"
		;;
	api-key)
		xcrun notarytool submit "$DMG_PATH" --wait \
			--key-id "$APP_STORE_CONNECT_API_KEY_ID" \
			--issuer "$APP_STORE_CONNECT_ISSUER_ID" \
			--key "$APP_STORE_CONNECT_API_KEY_PATH"
		;;
	*)
		echo "error: unknown notary credential kind: $NOTARY_KIND" >&2
		exit 1
		;;
esac

echo "==> Stapling"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
echo "Stapled: $DMG_PATH"
