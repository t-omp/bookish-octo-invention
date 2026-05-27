#!/bin/bash
set -ouex pipefail

### Install required packages
dnf5 install -y waydroid curl jq

mkdir -p /usr/share/waydroid-apks
### Install apkeep v1.0.0 (hardcoded, correct asset)
APKEEP_URL="https://github.com/EFForg/apkeep/releases/download/1.0.0/apkeep-x86_64-unknown-linux-gnu"

curl -fsSL "$APKEEP_URL" -o /usr/local/bin/apkeep
chmod +x /usr/local/bin/apkeep

### Optional: enable podman.socket
systemctl enable podman.socket
