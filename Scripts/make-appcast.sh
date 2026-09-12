#!/usr/bin/env bash
#
# Wraps Sparkle's generate_appcast once the SwiftPM artifacts are present.
#
# Usage:
#   Scripts/make-appcast.sh [directory-of-archives]
#
# The directory should contain the signed disk images (or zips) to describe.
# generate_appcast writes an appcast next to them. It signs enclosures with the
# EdDSA private key in the login keychain. This script does not invent an
# unsigned enclosure.
#
set -euo pipefail

usage() {
	sed -n '2,12p' "$0"
}

if [[ $# -gt 0 ]]; then
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
	esac
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

locate_generate_appcast() {
	local candidate
	local bin_path
	local -a candidates=()

	if bin_path="$(swift build --show-bin-path 2>/dev/null)"; then
		candidates+=("$bin_path/generate_appcast")
	fi

	candidates+=(
		"$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
		"$PROJECT_ROOT/.build/checkouts/Sparkle/bin/generate_appcast"
		"$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/bin/generate_appcast"
	)

	# Sparkle's tools sit next to the checkout artifacts:
	#   .build/checkouts/Sparkle/../artifacts/sparkle/Sparkle/bin/generate_appcast
	if [[ -d "$PROJECT_ROOT/.build/checkouts/Sparkle" ]]; then
		candidates+=("$PROJECT_ROOT/.build/checkouts/Sparkle/../artifacts/sparkle/Sparkle/bin/generate_appcast")
	fi

	while IFS= read -r candidate; do
		candidates+=("$candidate")
	done < <(find "$PROJECT_ROOT/.build" -type f -name generate_appcast 2>/dev/null | head -20)

	for candidate in "${candidates[@]}"; do
		if [[ -x "$candidate" ]]; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

GENERATE_APPCAST="$(locate_generate_appcast || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
	cat >&2 <<'EOF'
error: Sparkle's generate_appcast was not found in SwiftPM artifacts.

Resolve the package so the Sparkle tools land in .build:

    swift package resolve

Then rebuild:

    swift build
EOF
	exit 1
fi

ARCHIVE_DIR="${1:-$PROJECT_ROOT/build}"
if [[ ! -d "$ARCHIVE_DIR" ]]; then
	echo "error: not a directory: $ARCHIVE_DIR" >&2
	exit 1
fi

echo "==> generate_appcast: ${GENERATE_APPCAST#$PROJECT_ROOT/}"
APPCAST_ARGS=()
if [[ -f "$PROJECT_ROOT/Secrets/sparkle-ed25519-private" ]]; then
	APPCAST_ARGS+=(--ed-key-file "$PROJECT_ROOT/Secrets/sparkle-ed25519-private")
fi
"$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" "$ARCHIVE_DIR"
