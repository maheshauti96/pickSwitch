#!/usr/bin/env bash
# Resource-only branding refresh for an existing certificate-signed local build.
# Never rebuilds or replaces application logic. Run only after generate-icons.sh.
set -euo pipefail
if [[ "${1:-}" != "--apply" || "$#" != 1 ]]; then
  echo "Usage: bash Scripts/refresh-installed-brand.sh --apply"
  echo "Updates only the installed VortexFlow brand resources and signature; keeps a ZIP backup."
  exit 2
fi
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLED="/Applications/Vortexflow.app"
BINARY_REL="Contents/MacOS/Vortexflow"
RESOURCE_REL="Contents/Resources"
BRAND_SOURCE="$PROJECT_ROOT/Sources/VortexflowCore/Resources"
RESOURCES=(VortexflowMark.png MenuBarMark.png MenuBarMark@2x.png MenuBarMark@3x.png)
[[ -f "$INSTALLED/$BINARY_REL" ]] || { echo "Installed app not found" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED/Contents/Info.plist")" == io.vortexflow.Vortexflow ]] || exit 1
for resource in "${RESOURCES[@]}"; do [[ -f "$BRAND_SOURCE/$resource" ]] || exit 1; done
[[ -f "$PROJECT_ROOT/Resources/AppIcon.icns" ]] || exit 1
codesign --verify --deep --strict "$INSTALLED"
ORIGINAL_REQUIREMENT="$(codesign -d -r- "$INSTALLED" 2>&1 | sed -n 's/^designated => //p')"
ORIGINAL_CERT="$(printf '%s' "$ORIGINAL_REQUIREMENT" | sed -n 's/.*certificate root = H"\([0-9a-fA-F]*\)".*/\1/p')"
[[ "${#ORIGINAL_CERT}" == 40 ]] || { echo "Expected a certificate-signed local development build" >&2; exit 1; }
SIGN_IDENTITY="${VORTEXFLOW_SIGN_IDENTITY:-$ORIGINAL_CERT}"

code_fingerprint() {
  local binary="$1" arch
  for arch in $(lipo -archs "$binary"); do
    printf '%s ' "$arch"
    otool -arch "$arch" -s __TEXT __text "$binary" |
      awk '/^[0-9a-fA-F]+[[:space:]]/ { seen=1; print } END { if (!seen) exit 1 }' |
      shasum -a 256
  done
}
ORIGINAL_CODE="$(code_fingerprint "$INSTALLED/$BINARY_REL")"
ORIGINAL_FILE="$(shasum -a 256 "$INSTALLED/$BINARY_REL" | awk '{print $1}')"
WORK="$(mktemp -d -t vortexflow-brand-refresh)"
STAGED="$WORK/Vortexflow.app"
PREVIOUS="$WORK/previous.app"
COMMITTED=0
cleanup() {
  local status=$?
  if [[ "$COMMITTED" == 0 && -d "$PREVIOUS" ]]; then
    if [[ -e "$INSTALLED" ]]; then mv "$INSTALLED" "$WORK/failed.app"; fi
    mv "$PREVIOUS" "$INSTALLED"
    echo "Restored the original app after an incomplete refresh." >&2
  fi
  if [[ "$COMMITTED" == 1 && -d "$WORK" && "$(basename "$WORK")" == vortexflow-brand-refresh.* ]]; then
    rm -rf "$WORK"
  elif [[ "$status" != 0 ]]; then
    echo "Staging evidence retained at: $WORK" >&2
  fi
}
trap cleanup EXIT

ditto "$INSTALLED" "$STAGED"
[[ "$(shasum -a 256 "$STAGED/$BINARY_REL" | awk '{print $1}')" == "$ORIGINAL_FILE" ]] || exit 1
for resource in "${RESOURCES[@]}"; do cp "$BRAND_SOURCE/$resource" "$STAGED/$RESOURCE_REL/$resource"; done
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$STAGED/$RESOURCE_REL/AppIcon.icns"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none \
  --preserve-metadata=identifier,entitlements,requirements,flags "$STAGED"
codesign --verify --deep --strict "-R=$ORIGINAL_REQUIREMENT" "$STAGED"
[[ "$(code_fingerprint "$STAGED/$BINARY_REL")" == "$ORIGINAL_CODE" ]] || { echo "Executable code changed; refusing installation" >&2; exit 1; }

BACKUP_DIR="$PROJECT_ROOT/build/brand-backups"
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/Vortexflow-before-logo-$(date '+%Y%m%d-%H%M%S').zip"
[[ ! -e "$BACKUP" ]] || exit 1
ditto -c -k --sequesterRsrc --keepParent "$INSTALLED" "$BACKUP"
unzip -tq "$BACKUP" >/dev/null

# Stop only the installed utility, never another Vortexflow executable or probe.
RUNNING_PIDS="$(pgrep -f '^/Applications/Vortexflow.app/Contents/MacOS/Vortexflow$' || true)"
if [[ -n "$RUNNING_PIDS" ]]; then
  while IFS= read -r pid; do kill -TERM "$pid"; done <<< "$RUNNING_PIDS"
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f '^/Applications/Vortexflow.app/Contents/MacOS/Vortexflow$' >/dev/null || break
    sleep 0.2
  done
  if pgrep -f '^/Applications/Vortexflow.app/Contents/MacOS/Vortexflow$' >/dev/null; then
    echo "App did not quit; original installation was not modified." >&2
    exit 1
  fi
fi
mv "$INSTALLED" "$PREVIOUS"
ditto "$STAGED" "$INSTALLED"
codesign --verify --deep --strict "-R=$ORIGINAL_REQUIREMENT" "$INSTALLED"
[[ "$(code_fingerprint "$INSTALLED/$BINARY_REL")" == "$ORIGINAL_CODE" ]] || exit 1
for resource in "${RESOURCES[@]}"; do cmp -s "$BRAND_SOURCE/$resource" "$INSTALLED/$RESOURCE_REL/$resource"; done
cmp -s "$PROJECT_ROOT/Resources/AppIcon.icns" "$INSTALLED/$RESOURCE_REL/AppIcon.icns"
COMMITTED=1
touch "$INSTALLED"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$INSTALLED" || echo "Note: Finder may refresh its cached icon after reopening." >&2
fi
echo "Refreshed: $INSTALLED"
echo "Backup: $BACKUP"
echo "Preserved designated requirement: $ORIGINAL_REQUIREMENT"
echo "Executable instruction fingerprints unchanged:"
printf '%s\n' "$ORIGINAL_CODE"
echo "Reopen VortexFlow to load the new menu-bar and window artwork."
