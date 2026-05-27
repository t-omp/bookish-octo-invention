#!/bin/bash
set -ouex pipefail

### Install required packages
dnf5 install -y waydroid curl jq

mkdir -p /usr/share/waydroid-apks

# Install apkeep (always latest)
TMPDIR=$(mktemp -d)

# Resolve the latest release tag (e.g. "v0.12.0")
LATEST_TAG=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
  https://github.com/EFForg/apkeep/releases/latest | awk -F'/' '{print $NF}')

# Construct the correct tarball name
TARBALL="apkeep-${LATEST_TAG}-x86_64-unknown-linux-musl.tar.gz"
TARBALL_URL="https://github.com/EFForg/apkeep/releases/download/${LATEST_TAG}/${TARBALL}"

echo "Downloading apkeep from: $TARBALL_URL"

curl -fsSL "$TARBALL_URL" -o "$TMPDIR/apkeep.tar.gz"
tar -xzf "$TMPDIR/apkeep.tar.gz" -C "$TMPDIR"

install -Dm755 "$TMPDIR/apkeep" /usr/local/bin/apkeep
rm -rf "$TMPDIR"


### Optional: enable podman.socket
systemctl enable podman.socket
