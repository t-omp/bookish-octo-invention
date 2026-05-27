
set -euo pipefail

if [ ! -f /var/lib/waydroid/waydroid.cfg ]; then
    waydroid init \
      -c https://ota.waydro.id/system \
      -v https://ota.waydro.id/vendor
fi