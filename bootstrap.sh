#!/usr/bin/env bash
# =============================================================================
# SCROW — one-line bootstrap (two-stage)
# =============================================================================
# Stage 1 (this script): download ONE tiny archive (installer-core.tar.gz,
# ~28 KB) with real progress, verify it, unpack it, and exec the SCROW
# terminal UI immediately. No git, no clone, no long scans.
#
# Stage 2 (lazy): the full ~50 MB component set is fetched by the installer
# itself — with real progress — only the first time an operation actually
# needs it. Never during startup.
#
# Uses curl only, so it works on a bare system that has no git yet.
#
#   curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash
#
# Environment overrides:
#   SCROW_BOOT_DIR       where the installer core is fetched (default:
#                        ~/.local/share/scrow/bootstrap)
#   SCROW_BOOT_BRANCH    branch to fetch (default: main)
#   SCROW_BOOT_LOG       where bootstrap diagnostics are logged (default:
#                        ~/.local/share/scrow/bootstrap.log)
#
# SCROW_REPO_URL / SCROW_TARBALL_URL are honored by the installer when it
# fetches the component files on first install.
# =============================================================================

set -uo pipefail

SCROW_BOOT_DIR="${SCROW_BOOT_DIR:-$HOME/.local/share/scrow/bootstrap}"
SCROW_BOOT_BRANCH="${SCROW_BOOT_BRANCH:-main}"
SCROW_BOOT_LOG="${SCROW_BOOT_LOG:-$HOME/.local/share/scrow/bootstrap.log}"

SCROW_CORE_URL="https://raw.githubusercontent.com/midn8crow/scrow/$SCROW_BOOT_BRANCH/installer-core.tar.gz"

# Files that must be present inside the unpacked archive. Everything else in
# the repository — dotfiles, themes, cursors, binaries — is fetched lazily by
# the installer when a component is actually installed.
SCROW_CORE_FILES=(
    install.sh
    VERSION
    installer/scrow
    installer/core.sh
    installer/state.sh
    installer/config.sh
    installer/backup.sh
    installer/sysd.sh
    installer/package.sh
    installer/components.sh
    installer/ownership.sh
    installer/engine.sh
    installer/menu.sh
)

printf 'SCROW · Arch Linux · Hyprland\n\n'

if ! command -v curl >/dev/null 2>&1; then
    printf 'SCROW: curl is required to download the installer.\n' >&2
    exit 1
fi

mkdir -p "$SCROW_BOOT_DIR"

# -----------------------------------------------------------------------------
# Diagnostics / logging helpers
# -----------------------------------------------------------------------------

scrow_boot_log() {
    mkdir -p "$(dirname "$SCROW_BOOT_LOG")"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$SCROW_BOOT_LOG" 2>/dev/null || true
}

scrow_die() {
    printf 'SCROW: %s\n' "$1" >&2
    printf 'Please check your network, then retry:\n' >&2
    printf '  curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash\n' >&2
    printf 'Details: %s\n' "$SCROW_BOOT_LOG" >&2
    exit 1
}

# Map a curl exit code to the most likely cause. Only called after retries and
# the IPv4 fallback have already run, so it can point at the real problem.
scrow_curl_reason() {
    local rc="$1" host="$2"
    case "$rc" in
        6)  echo "could not resolve $host (DNS lookup failed). Other websites may still work — this is a DNS problem for GitHub specifically." ;;
        7)  echo "could not connect to $host." ;;
        28) echo "timed out reaching $host (DNS or connection too slow)." ;;
        18) echo "download from $host was incomplete (connection closed before all data arrived)." ;;
        22) echo "$host returned an HTTP error (status 4xx/5xx)." ;;
        35) echo "TLS/SSL handshake failed with $host." ;;
        52) echo "$host closed the connection without sending any data." ;;
        56) echo "$host interrupted the connection during the download." ;;
        77) echo "could not verify the SSL certificate of $host." ;;
        *)  echo "could not download from $host (curl exit $rc)." ;;
    esac
}

# -----------------------------------------------------------------------------
# Download + progress
# -----------------------------------------------------------------------------

# Stream stdin to stdout while rendering a single updating "Preparing SCROW…"
# percentage line. The percentage is real: bytes received / total length.
#
# Chunking goes through a temp file with a `wc -c` byte count — NOT through a
# bash variable and NOT via `while dd ...`:
#   - bash variables are C strings and silently drop NUL bytes, which would
#     corrupt the gzip archive.
#   - GNU dd returns 0 even on EOF (EOF is not an error), so `while dd ...`
#     would loop forever once the stream ends.
# A temp-file round-trip keeps the bytes intact and the loop bounded.
scrow_boot_progress() {
    local total="$1"
    local -i done=0 n
    local tmp
    tmp="$(mktemp 2>/dev/null)" || tmp="${TMPDIR:-/tmp}/scrow-progress.$$"
    trap 'rm -f "$tmp"' RETURN
    while :; do
        dd bs=4096 count=1 2>/dev/null > "$tmp"
        n="$(wc -c < "$tmp" 2>/dev/null)"
        (( n == 0 )) && break
        done=$(( done + n ))
        if (( total > 0 )); then
            printf '\r\033[KPreparing SCROW... %3d%%' "$(( done * 100 / total ))" >&2
        fi
        cat "$tmp"
        : > "$tmp"
    done
    printf '\r\033[KPreparing SCROW... 100%%\n' >&2
}

# One download attempt with real progress and bounded phases. On failure the
# partial file is removed and curl's stderr is appended to the bootstrap log.
# $1 = url  $2 = output path  $3 = expected size (0 = unknown)  $4 = "4" for IPv4
scrow_curl_with_progress() {
    local url="$1" out="$2" total="$3" force4="$4" rc
    local -a curlopts=( -fL --proto '=https' --connect-timeout 15 --max-time 120 \
        --retry 3 --retry-delay 2 --retry-all-errors )
    [[ "$force4" == "4" ]] && curlopts+=( -4 )
    curl "${curlopts[@]}" -o - "$url" 2>"${out}.err" | scrow_boot_progress "$total" > "$out"
    rc=${PIPESTATUS[0]}
    if (( rc != 0 )); then
        rm -f "$out"
        scrow_boot_log "curl failed (exit $rc): $url"
        cat "${out}.err" >> "$SCROW_BOOT_LOG" 2>/dev/null || true
    fi
    rm -f "${out}.err"
    return "$rc"
}

# Fetch the core archive with an IPv4 fallback. Returns 0 on success.
scrow_fetch_core() {
    local url="$1" out="$2"
    local host="${url#https://}"
    host="${host%%/*}"
    local total=0
    # Probe the expected size once (bounded, silent) so progress is real.
    total="$(curl -sIL --proto '=https' --connect-timeout 8 --max-time 20 "$url" 2>/dev/null \
        | awk -F': ' 'tolower($1) == "content-length" { gsub("\r", ""); print $2; exit }')"
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    # Use `cmd && return`, NOT `if cmd; then ...; fi`: an if-statement with no
    # else branch reports $? = 0 when the condition fails, which would erase
    # the curl exit code we capture below.
    scrow_curl_with_progress "$url" "$out" "$total" "" && return 0
    scrow_curl_with_progress "$url" "$out" "$total" "4" && return 0
    # Capture $? FIRST: the next line's assignment would reset it to 0 (bash
    # reports 0 for an assignment-only command).
    SCROW_BOOT_RC=$?
    SCROW_BOOT_HOST="$host"
    return 1
}

# -----------------------------------------------------------------------------
# Fetch the installer core (one archive)
# -----------------------------------------------------------------------------

SCROW_BOOT_TMP="$SCROW_BOOT_DIR/installer-core.tar.gz.tmp"
rm -f "$SCROW_BOOT_TMP"
if ! scrow_fetch_core "$SCROW_CORE_URL" "$SCROW_BOOT_TMP"; then
    SCROW_BOOT_REASON="$(scrow_curl_reason "$SCROW_BOOT_RC" "$SCROW_BOOT_HOST")"
    scrow_boot_log "fetch failed: $SCROW_BOOT_REASON (url $SCROW_CORE_URL, curl exit $SCROW_BOOT_RC)"
    scrow_die "could not download the SCROW installer — $SCROW_BOOT_REASON"
fi

# -----------------------------------------------------------------------------
# Verify + unpack
# -----------------------------------------------------------------------------

if ! gzip -t "$SCROW_BOOT_TMP" 2>/dev/null; then
    rm -f "$SCROW_BOOT_TMP"
    scrow_boot_log "archive corrupt after download"
    scrow_die "the downloaded SCROW installer is incomplete or corrupt."
fi

SCROW_BOOT_XDIR="$SCROW_BOOT_DIR/.extract"
rm -rf "$SCROW_BOOT_XDIR"
mkdir -p "$SCROW_BOOT_XDIR"
if ! tar -xzf "$SCROW_BOOT_TMP" -C "$SCROW_BOOT_XDIR"; then
    rm -rf "$SCROW_BOOT_XDIR" "$SCROW_BOOT_TMP"
    scrow_boot_log "archive could not be unpacked"
    scrow_die "could not unpack the SCROW installer."
fi

SCROW_BOOT_OK=1
for rel in "${SCROW_CORE_FILES[@]}"; do
    if [[ ! -s "$SCROW_BOOT_XDIR/$rel" ]]; then
        scrow_boot_log "missing or empty after unpack: $rel"
        SCROW_BOOT_OK=0
    fi
done
if (( SCROW_BOOT_OK == 0 )); then
    rm -rf "$SCROW_BOOT_XDIR" "$SCROW_BOOT_TMP"
    scrow_die "the downloaded SCROW installer is incomplete."
fi

# Merge the fresh core into place (repeated runs stay safe: old files are
# overwritten, unrelated files in the boot dir are left alone).
cp -a "$SCROW_BOOT_XDIR"/. "$SCROW_BOOT_DIR"/
rm -rf "$SCROW_BOOT_XDIR" "$SCROW_BOOT_TMP"

# -----------------------------------------------------------------------------
# Launch
# -----------------------------------------------------------------------------

printf 'Launching SCROW...\n\n'

# When run via `curl ... | bash`, bash's stdin is the curl pipe, which is
# already at EOF by the time the installer starts. The interactive TUI's
# `read` would then see EOF and exit immediately. Give the installer the
# user's actual terminal instead. The subshell probe actually tries to open
# /dev/tty, so headless/CI runs (no controlling terminal) fall through and
# keep their current stdin unchanged.
if [[ ! -t 0 ]] && ( : < /dev/tty ) 2>/dev/null; then
    exec bash "$SCROW_BOOT_DIR/install.sh" "$@" < /dev/tty
fi
exec bash "$SCROW_BOOT_DIR/install.sh" "$@"
