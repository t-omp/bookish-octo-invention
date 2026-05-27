#!/usr/bin/env bash
set -euo pipefail

FDROID_METADATA="https://f-droid.org/api/v1/packages"
FDROID_REPO="https://f-droid.org/repo"
FLAGS_DIR="/var/lib/waydroid/.installed"
BUNDLED_DIR="/usr/share/waydroid-apks"

# ── APK list ──────────────────────────────────────────────────────────────────
# Format: "pkg|source"
# Sources:
#   fdroid              — F-Droid API (recommended for FOSS apps)
#   url|https://...     — direct URL, follows redirects (e.g. APKMirror)
#   bundled             — APK at $BUNDLED_DIR/<pkg>.apk, baked into image
APKS=(
    "org.fdroid.fdroid|fdroid"
    "com.aurora.store|fdroid"
)

# ── Phase 1: APK installation ─────────────────────────────────────────────────
mkdir -p "$FLAGS_DIR"

all_done=true
for entry in "${APKS[@]}"; do
    pkg="${entry%%|*}"
    [[ ! -f "${FLAGS_DIR}/${pkg}" ]] && { all_done=false; break; }
done
if [[ "$all_done" == true ]]; then
    echo "All APKs already installed, skipping."
    exit 0
fi

WAITED=0
until waydroid status 2>/dev/null | grep -q "Session: RUNNING"; do
    if (( WAITED >= 120 )); then
        echo "Timed out waiting for Waydroid session — will retry on next boot."
        exit 0
    fi
    sleep 5
    (( WAITED += 5 ))
done

waydroid_install() {
    local pkg="$1" apk="$2"
    local flag="${FLAGS_DIR}/${pkg}"

    if waydroid app list 2>/dev/null | grep -q "^${pkg}$"; then
        echo "$pkg found in Android, marking done."
        touch "$flag"
        return 0
    fi

    if waydroid app install "$apk"; then
        touch "$flag"
        echo "$pkg installed."
    else
        echo "Install failed: $pkg"
        return 1
    fi
}

install_fdroid() {
    local pkg="$1"
    local flag="${FLAGS_DIR}/${pkg}"
    [[ -f "$flag" ]] && { echo "$pkg already installed, skipping."; return 0; }

    echo "Resolving $pkg from F-Droid..."
    local version_code
    version_code=$(curl -fsSL "${FDROID_METADATA}/${pkg}" \
        | jq -r '.suggestedVersionCode') \
        || { echo "Failed to resolve $pkg — skipping."; return 1; }

    if [[ -z "$version_code" || "$version_code" == "null" ]]; then
        echo "No version code for $pkg — skipping."
        return 1
    fi

    local url="${FDROID_REPO}/${pkg}_${version_code}.apk"
    echo "Downloading $pkg version $version_code from F-Droid..."

    local tmp
    tmp=$(mktemp --suffix=.apk)
    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
        echo "Download failed: $pkg"
        rm -f "$tmp"
        return 1
    fi

    waydroid_install "$pkg" "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

install_url() {
    local pkg="$1" url="$2"
    local flag="${FLAGS_DIR}/${pkg}"
    [[ -f "$flag" ]] && { echo "$pkg already installed, skipping."; return 0; }

    echo "Downloading $pkg from URL..."
    local tmp
    tmp=$(mktemp --suffix=.apk)
    if ! curl -fsSL --retry 3 --retry-delay 2 -L -o "$tmp" "$url"; then
        echo "Download failed: $pkg"
        rm -f "$tmp"
        return 1
    fi

    waydroid_install "$pkg" "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

install_bundled() {
    local pkg="$1"
    local flag="${FLAGS_DIR}/${pkg}"
    [[ -f "$flag" ]] && { echo "$pkg already installed, skipping."; return 0; }

    local apk="${BUNDLED_DIR}/${pkg}.apk"
    if [[ ! -f "$apk" ]]; then
        echo "Bundled APK not found: $apk — skipping."
        return 1
    fi

    echo "Installing bundled $pkg..."
    waydroid_install "$pkg" "$apk"
}

failed=()
for entry in "${APKS[@]}"; do
    pkg="${entry%%|*}"
    source="${entry#*|}"
    source_type="${source%%|*}"

    case "$source_type" in
        fdroid)
            install_fdroid "$pkg" || failed+=("$pkg")
            ;;
        url)
            url="${source#url|}"
            install_url "$pkg" "$url" || failed+=("$pkg")
            ;;
        bundled)
            install_bundled "$pkg" || failed+=("$pkg")
            ;;
        *)
            echo "Unknown source '$source_type' for $pkg — skipping."
            failed+=("$pkg")
            ;;
    esac
done

if (( ${#failed[@]} > 0 )); then
    echo "Failed (will retry on next boot): ${failed[*]}"
    exit 0
fi

echo "All APKs installed successfully."
