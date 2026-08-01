#!/bin/bash
# Pacman/paru pre-install security scanner.
#
# Installed as an alpm PreTransaction hook: on every `pacman -Syu` / `pacman -S`
# / `paru -Syu` / `paru -S` transaction (including locally built AUR packages),
# the hook receives the .pkg.tar.zst paths on stdin and this script extracts and
# scans each one BEFORE it is installed. Hits are printed in the pacman output
# and logged. Exit code is 1 when anything is found, so the hook's AbortOnFail
# setting decides whether suspicious updates get blocked.
#
# Patterns come from aur-check.sh (single source of truth).

PATTERN_SRC="/home/shadhin/security-hardening/aur-check.sh"

LOG=/var/log/update-scan.log
[ -w /var/log ] || LOG=/tmp/update-scan.log

HITS=0
SCANNED=0
EXT_DIR=""

cleanup() {
    [ -n "$EXT_DIR" ] && rm -rf "$EXT_DIR" 2>/dev/null
}
trap cleanup EXIT

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null
}

# Load the same pattern set used by aur-check.sh, without running it.
PATTERN_DEF=$(sed -n '/^declare -A PATTERNS=(/,/^)/p' "$PATTERN_SRC" 2>/dev/null)
if printf '%s' "$PATTERN_DEF" | grep -q '^declare -A PATTERNS='; then
    eval "$PATTERN_DEF"
else
    log "WARNING: could not load patterns from $PATTERN_SRC"
fi
if ! declare -p PATTERNS >/dev/null 2>&1; then
    declare -A PATTERNS=()
fi

# Scan one extracted file. Mirrors scan_file() from aur-check.sh.
scan_file() {
    local f="$1" prefix="$2" base ext code pattern
    [ -f "$f" ] || return 0
    base=${f##*/}
    case "$base" in
        README*|LICENSE*|COPYING*|CHANGELOG*|NEWS|AUTHORS|INSTALL|CONTRIBUTING*|HACKING*) return 0 ;;
        Cargo.lock|package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|pnpm-lock.yml|poetry.lock|Gemfile.lock|composer.lock|go.sum|mix.lock) return 0 ;;
    esac
    ext=${base##*.}
    case "$ext" in
        md|txt|rst|adoc|sample|bak|orig|yml|yaml) return 0 ;;
    esac
    grep -Iq . "$f" 2>/dev/null || return 0
    code=$(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null | tr '\n' ' ')
    [ -n "$code" ] || return 0
    for pattern in "${!PATTERNS[@]}"; do
        if printf '%s' "$code" | grep -qiE -- "$pattern"; then
            printf '  [SUSPICIOUS] %s : %s - %s\n' "${f#"$prefix"/}" "$pattern" "${PATTERNS[$pattern]}"
            HITS=$((HITS + 1))
        fi
    done
}

# Scan one package archive.
scan_package() {
    local pkg="$1" sub
    [ -f "$pkg" ] || return 0
    SCANNED=$((SCANNED + 1))
    sub="$EXT_DIR/$(basename "$pkg")"
    mkdir -p "$sub"
    if ! bsdtar -xf "$pkg" -C "$sub" 2>/dev/null; then
        printf '  [ERROR] Failed to extract %s\n' "$(basename "$pkg")"
        log "ERROR: failed to extract $pkg"
        return 0
    fi
    printf '  Scanning %s ...\n' "$(basename "$pkg")"
    local f
    while IFS= read -r -d '' f; do
        scan_file "$f" "$sub"
    done < <(find "$sub" -type f -print0)
}

if [ -n "$1" ]; then
    EXT_DIR=$(mktemp -d /var/tmp/update-scan.XXXXXX 2>/dev/null) || EXT_DIR=$(mktemp -d /tmp/update-scan.XXXXXX)
    for pkg in "$@"; do
        scan_package "$pkg"
    done
else
    if [ ! -t 0 ]; then
        EXT_DIR=$(mktemp -d /var/tmp/update-scan.XXXXXX 2>/dev/null) || EXT_DIR=$(mktemp -d /tmp/update-scan.XXXXXX)
        while IFS= read -r target; do
            [ -n "$target" ] || continue
            if [ -f "$target" ]; then
                scan_package "$target"
            elif [ -f "/var/cache/pacman/pkg/$target" ]; then
                scan_package "/var/cache/pacman/pkg/$target"
            else
                mapfile -t files < <(find /var/cache/pacman/pkg -maxdepth 1 -type f -name "$target-*.pkg.tar.zst" 2>/dev/null | sort -V)
                [ "${#files[@]}" -gt 0 ] && scan_package "${files[-1]}"
            fi
        done
    else
        printf 'Usage: %s <package.pkg.tar.zst>...   (or pipe package paths on stdin)\n' "$0"
        exit 0
    fi
fi

if [ "$HITS" -gt 0 ]; then
    printf '  [WARNING] %d suspicious pattern(s) found in %d package(s). Logged to %s\n' "$HITS" "$SCANNED" "$LOG"
    log "SCAN: $HITS hit(s) in $SCANNED package(s)"
    exit 1
fi
log "SCAN: clean ($SCANNED package(s) scanned)"
exit 0
