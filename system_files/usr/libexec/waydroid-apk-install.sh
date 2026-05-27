#!/usr/bin/env bash
set -euo pipefail

FDROID_METADATA="https://f-droid.org/api/v1/packages"
FDROID_REPO="https://f-droid.org/repo"

FLAGS_DIR="/var/lib/waydroid-extra/installed"
BUNDLED_DIR="/usr/share/waydroid-apks"
TMPDIR="/var/tmp"

# Format:
#   pkg|fdroid
#   pkg|url|https://...
#   pkg|apkeep|store_pkg[@version]
#   pkg|bundled
APKS=(
    "org.fdroid.fdroid|fdroid"
    "com.aurora.store|fdroid"
    "com.spotify.music|apkeep|com.spotify.music"
    "com.aige.hipaint|apkeep|com.aige.hipaint@latest"
)

mkdir -p "$FLAGS_DIR"

log() {
    echo "[waydroid-apk-install] $*"
}

# ── Wait for Waydroid session ────────────────────────────────────────────────
WAITED=0
log "Waiting for Waydroid session to become RUNNING..."

until waydroid status 2>/dev/null | grep -q "Session: RUNNING"; do
    if (( WAITED >= 180 )); then
        log "Timed out waiting for Waydroid session — will retry next boot."
        exit 0
    fi
    sleep 5
    (( WAITED += 5 ))
done

log "Waydroid session is RUNNING."

# ── Reliable app list ────────────────────────────────────────────────────────
get_app_list() {
    local tries=0 out
    while (( tries < 10 )); do
        if out=$(waydroid app list 2>/dev/null) && [[ -n "$out" ]]; then
            echo "$out"
            return 0
        fi
        sleep 2
        (( tries++ ))
    done
    echo ""
}

# ── Core installer ───────────────────────────────────────────────────────────
waydroid_install() {
    local pkg="$1" apk="$2"
    local flag="${FLAGS_DIR}/${pkg}"

    if get_app_list | grep -q "^${pkg}$"; then
        log "$pkg already installed in Android — marking done."
        touch "$flag"
        return 0
    fi

    if waydroid app install "$apk"; then
        log "$pkg installed."
        touch "$flag"
        return 0
    else
        log "Install failed: $pkg"
        return 1
    fi
}

# ── F-Droid ──────────────────────────────────────────────────────────────────
install_fdroid() {
    local pkg="$1"
    local flag="${FLAGS_DIR}/${pkg}"

    [[ -f "$flag" ]] && { log "$pkg already installed, skipping."; return 0; }

    log "Resolving $pkg from F-Droid..."

    local version_code
    version_code=$(curl -fsSL "${FDROID_METADATA}/${pkg}" \
        | jq -r '.suggestedVersionCode // .packages[].versionCode' \
        | head -n1)

    if [[ -z "$version_code" || "$version_code" == "null" ]]; then
        log "No version code for $pkg — skipping."
        return 1
    fi

    local url="${FDROID_REPO}/${pkg}_${version_code}.apk"
    log "Downloading $pkg version $version_code..."

    local tmp
    tmp=$(mktemp --suffix=.apk)

    if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"; then
        log "Download failed: $pkg"
        rm -f "$tmp"
        return 1
    fi

    waydroid_install "$pkg" "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# ── URL ──────────────────────────────────────────────────────────────────────
install_url() {
    local pkg="$1" url="$2"
    local flag="${FLAGS_DIR}/${pkg}"

    [[ -f "$flag" ]] && { log "$pkg already installed, skipping."; return 0; }

    log "Downloading $pkg from URL..."
    local tmp
    tmp=$(mktemp --suffix=.apk)

    if ! curl -fsSL --retry 3 --retry-delay 2 -L -o "$tmp" "$url"; then
        log "Download failed: $pkg"
        rm -f "$tmp"
        return 1
    fi

    waydroid_install "$pkg" "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# ── Bundled ──────────────────────────────────────────────────────────────────
install_bundled() {
    local pkg="$1"
    local flag="${FLAGS_DIR}/${pkg}"
    local apk="${BUNDLED_DIR}/${pkg}.apk"

    [[ -f "$flag" ]] && { log "$pkg already installed, skipping."; return 0; }

    if [[ ! -f "$apk" ]]; then
        log "Bundled APK missing: $apk"
        return 1
    fi

    log "Installing bundled $pkg..."
    waydroid_install "$pkg" "$apk"
}

# ── apkeep ───────────────────────────────────────────────────────────────────
install_apkeep() {
    local pkg="$1" app_id="$2"
    local flag="${FLAGS_DIR}/${pkg}"

    [[ -f "$flag" ]] && { log "$pkg already installed, skipping."; return 0; }

    if ! command -v apkeep >/dev/null 2>&1; then
        log "apkeep not found in PATH — skipping $pkg."
        return 1
    fi

    log "Downloading $pkg via apkeep (id: $app_id)..."

    local tmp
    tmp=$(mktemp --suffix=.apk)
    local tmpdir
    tmpdir=$(mktemp -d)

    if ! apkeep -a "$app_id" -o "$tmpdir"; then
        log "apkeep failed for $pkg ($app_id)"
        rm -rf "$tmpdir"
        rm -f "$tmp"
        return 1
    fi

    local dl_apk
    dl_apk=$(find "$tmpdir" -maxdepth 1 -type f -name '*.apk' | head -n1 || true)
    if [[ -z "$dl_apk" ]]; then
        log "apkeep did not produce an APK for $pkg"
        rm -rf "$tmpdir"
        rm -f "$tmp"
        return 1
    fi

    mv "$dl_apk" "$tmp"
    rm -rf "$tmpdir"

    waydroid_install "$pkg" "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# ── Main loop ────────────────────────────────────────────────────────────────
failed=()

for entry in "${APKS[@]}"; do
    IFS='|' read -r pkg source_type source_arg <<<"$entry"

    case "$source_type" in
        fdroid)
            install_fdroid "$pkg" || failed+=("$pkg")
            ;;
        url)
            install_url "$pkg" "$source_arg" || failed+=("$pkg")
            ;;
        bundled)
            install_bundled "$pkg" || failed+=("$pkg")
            ;;
        apkeep)
            install_apkeep "$pkg" "$source_arg" || failed+=("$pkg")
            ;;
        *)
            log "Unknown source '$source_type' for $pkg"
            failed+=("$pkg")
            ;;
    esac
done

if (( ${#failed[@]} > 0 )); then
    log "Failed (will retry next boot): ${failed[*]}"
    exit 0
fi

log "All APKs installed successfully."
exit 0
