#!/usr/bin/env bash
set -euo pipefail

FDROID_METADATA="https://f-droid.org/api/v1/packages"
FDROID_REPO="https://f-droid.org/repo"
FLAGS_DIR="/var/lib/waydroid/.installed"

# ── APK list — add package IDs here ──────────────────────────────────────────
APKS=(
    org.fdroid.fdroid
    com.aurora.store
)

# ── Phase 1: init ─────────────────────────────────────────────────────────────
if [[ ! -f /var/lib/waydroid/waydroid.cfg ]]; then
    waydroid init \
        -c https://ota.waydro.id/system \
        -v https://ota.waydro.id/vendor
fi

# ── Phase 2: APK installation ─────────────────────────────────────────────────
mkdir -p "$FLAGS_DIR"

# Check if all packages already installed — skip session wait entirely
all_done=true
for pkg in "${APKS[@]}"; do
    [[ ! -f "${FLAGS_DIR}/${pkg}" ]] && { all_done=false; break; }
done
if [[ "$all_done" == true ]]; then
    echo "All APKs already installed, skipping."
    exit 0
fi

# Wait for a user session
WAITED=0
until waydroid status 2>/dev/null | grep -q "Session: RUNNING"; do
    if (( WAITED >= 120 )); then
        echo "Timed out waiting for Waydroid session — will retry on next boot."
        exit 0
    fi
    sleep 5
    (( WAITED += 5 ))
done

install_from_fdroid() {
    local pkg="$1"
    local flag="${FLAGS_DIR}/${pkg}"

    # Already succeeded on a previous boot
    if [[ -f "$flag" ]]; then
        echo "$pkg already installed, skipping."
        return 0
    fi

    # Already installed in Android (e.g. pre-seeded image)
    if waydroid app list 2>/dev/null | grep -q "^${pkg}$"; then
        echo "$pkg found in Android, marking done."
        touch "$flag"
        return 0
    fi

    echo "Resolving $pkg from F-Droid..."
    local version_code
    version_code=$(curl -fsSL "${FDROID_METADATA}/${pkg}" \
        | jq -r '.suggestedVersionCode') \
        || { echo "Failed to resolve $pkg — skipping."; return 1; }

    if [[ -z "$version_code" || "$version_code" == "null" ]]; then
        echo "No version code returned for $pkg — skipping."
        return 1
    fi

    local url="${FDROID_REPO}/${pkg}_${version_code}.apk"
    echo "Downloading $pkg version $version_code..."

    local tmp
    tmp=$(mktemp --suffix=.apk)

    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
        echo "Download failed: $pkg"
        rm -f "$tmp"
        return 1
    fi

    if waydroid app install "$tmp"; then
        echo "$pkg installed successfully."
        touch "$flag"
    else
        echo "Install failed: $pkg — will retry on next boot."
        rm -f "$tmp"
        return 1
    fi

    rm -f "$tmp"
}

# ── Run installs, track overall success ───────────────────────────────────────
failed=()
for pkg in "${APKS[@]}"; do
    install_from_fdroid "$pkg" || failed+=("$pkg")
done

if (( ${#failed[@]} > 0 )); then
    echo "The following APKs failed and will be retried on next boot: ${failed[*]}"
    exit 0  # soft exit — don't fail the service, per-package flags handle retry
fi

echo "All APKs installed successfully."