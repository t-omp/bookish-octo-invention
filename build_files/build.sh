#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux 

# Install low-memory and eMMC-friendly utilities
# zram-generator-defaults creates a compressed swap device on boot
dnf5 install -y zram-generator-defaults util-linux || true

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

# Disk and memory tuning files are provided under `system_files/etc/` and
# will be installed into the image; keep them version controlled there.

# Enable periodic fstrim to maintain eMMC performance
systemctl enable fstrim.timer || true

# Enable memory helpers for low-RAM systems
systemctl enable systemd-oomd || true
# Enable zram setup unit for the first zram device (if generated)
systemctl enable systemd-zram-setup@zram0.service || true
