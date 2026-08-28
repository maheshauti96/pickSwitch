#!/usr/bin/env bash
#
# Creates a self-signed code-signing certificate for local Vortexflow builds.
#
# Why this exists
# ---------------
# An ad-hoc signature (`codesign --sign -`) gives the app a different code identity
# on every build. macOS records permission grants against a code identity, so with
# ad-hoc signing:
#
#   * every rebuild looks like a brand-new app and loses its permissions, and
#   * stale records pile up under the same bundle identifier until macOS gets
#     confused and refuses to add the app to the privacy lists at all — the "+"
#     button appears to do nothing.
#
# A self-signed certificate fixes this. The signature's designated requirement then
# names the certificate rather than the exact binary bytes, so the identity stays
# the same across rebuilds and grants stick.
#
# What this does to your machine
# ------------------------------
# Adds one certificate named "Vortexflow Dev" to your *login* keychain. It is not a
# system-wide trust change, it grants nothing to anyone else, and it can be removed
# any time from Keychain Access or with:
#
#   security delete-certificate -c "Vortexflow Dev"
#
set -euo pipefail

IDENTITY_NAME="${1:-Vortexflow Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Note the absence of -v. A self-signed certificate is reported as untrusted
# (CSSMERR_TP_NOT_TRUSTED) and `-v` filters it out, but codesign still signs with it
# perfectly well — trust only affects *verifying* a signature, not producing one.
# Chasing trust would mean a system-wide keychain change for no benefit here.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
	echo "Certificate \"$IDENTITY_NAME\" already exists. Nothing to do."
	echo
	echo "Build with it using:  Scripts/build-app.sh --install"
	exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Generating a self-signed code-signing certificate: $IDENTITY_NAME"

# extendedKeyUsage=codeSigning is the part that makes codesign willing to use it.
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
	-keyout "$WORK_DIR/key.pem" \
	-out "$WORK_DIR/cert.pem" \
	-subj "/CN=$IDENTITY_NAME/O=Vortexflow/C=US" \
	-addext "basicConstraints=critical,CA:FALSE" \
	-addext "keyUsage=critical,digitalSignature" \
	-addext "extendedKeyUsage=critical,codeSigning" \
	2>/dev/null

# A throwaway transport password for the PKCS#12 blob. An empty password makes
# Apple's importer fail MAC verification, so use a real one; it never leaves this
# script and the file is deleted on exit.
P12_PASSWORD="$(openssl rand -hex 16)"

# The explicit legacy PBE and MAC algorithms matter. Apple's Security framework
# rejects the modern PKCS#12 defaults with "MAC verification failed".
openssl pkcs12 -export \
	-macalg sha1 \
	-keypbe PBE-SHA1-3DES \
	-certpbe PBE-SHA1-3DES \
	-out "$WORK_DIR/identity.p12" \
	-inkey "$WORK_DIR/key.pem" \
	-in "$WORK_DIR/cert.pem" \
	-name "$IDENTITY_NAME" \
	-passout pass:"$P12_PASSWORD" \
	2>/dev/null

echo "==> Importing into the login keychain"
# -T /usr/bin/codesign pre-authorises codesign to use the key, so builds do not
# stop on a keychain password prompt every time.
security import "$WORK_DIR/identity.p12" \
	-k "$KEYCHAIN" \
	-P "$P12_PASSWORD" \
	-T /usr/bin/codesign \
	-T /usr/bin/security \
	>/dev/null

# Best effort. The `-T /usr/bin/codesign` flags during import normally suffice; this
# is belt and braces for keychain configurations where they do not.
security set-key-partition-list \
	-S apple-tool:,apple:,codesign: \
	-s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

# Prove it works rather than trusting a listing: sign a throwaway binary.
echo "==> Verifying codesign can use it"
PROBE_DIR="$(mktemp -d)"
cp /bin/echo "$PROBE_DIR/probe"
if codesign --force --sign "$IDENTITY_NAME" "$PROBE_DIR/probe" >/dev/null 2>&1 &&
	codesign -dvv "$PROBE_DIR/probe" 2>&1 | grep -q "Authority=$IDENTITY_NAME"; then
	rm -rf "$PROBE_DIR"
else
	rm -rf "$PROBE_DIR"
	echo "error: \"$IDENTITY_NAME\" was imported but codesign cannot sign with it" >&2
	exit 1
fi

echo
echo "Created \"$IDENTITY_NAME\":"
security find-identity -p codesigning | grep "$IDENTITY_NAME" | sed 's/^/    /'
cat <<-NOTE

	It is reported as untrusted, which is expected and harmless: trust affects
	verifying signatures, not making them. What matters is that the identity now
	stays the same across rebuilds, so macOS can remember Vortexflow's permissions.

	Next, clear the stale records left behind by the earlier ad-hoc builds and
	reinstall:

	    tccutil reset All io.vortexflow.Vortexflow
	    Scripts/build-app.sh --install
NOTE
