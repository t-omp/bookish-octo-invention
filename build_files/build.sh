#!/bin/bash
set -ouex pipefail

### Install required packages
dnf5 install -y waydroid curl jq

### Install apkeep (always latest)
TMPDIR=$(mktemp -d)

# Fetch latest release tarball URL automatically
LATEST_URL=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
  https://github.com/EFForg/apkeep/releases/latest)

# Convert ".../tag/v0.12.0" → ".../download/v0.12.0/apkeep-v0.12.0-x86_64-unknown-linux-musl.tar.gz"
VERSION=$(basename "$LATEST_URL")
TARBALL_URL="https://github.com/EFForg/apkeep/releases/download/${VERSION}/apkeep-${VERSION}-x86_64-unknown-linux-musl.tar.gz"

curl -fsSL "$TARBALL_URL" -o "$TMPDIR/apkeep.tar.gz"
tar -xzf "$TMPDIR/apkeep.tar.gz" -C "$TMPDIR"

install -Dm755 "$TMPDIR/apkeep" /usr/local/bin/apkeep
rm -rf "$TMPDIR"

### Optional: enable podman.socket
systemctl enable podman.socket
