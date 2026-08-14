#!/usr/bin/env bash
# =============================================================================
# SCROW — one-line bootstrap
# =============================================================================
# Downloads only the self-contained installer core (~120 KB) and launches the
# SCROW terminal UI immediately. The ~50 MB component set is fetched by the
# installer itself — lazily, with real progress — the first time a component
# is actually installed. Never during startup.
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

SCROW_RAW_URL="https://raw.githubusercontent.com/midn8crow/scrow/$SCROW_BOOT_BRANCH"

# Files that make up the self-contained installer. Everything else in the
# repository — dotfiles, themes, cursors, binaries — is fetched lazily by the
# installer when a component is actually installed.
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

printf 'SCROW — Arch Linux • Hyprland\n\n'

if ! command -v curl >/dev/null 2>&1; then
    printf 'SCROW: curl is required to download the installer.\n' >&2
    exit 1
fi

mkdir -p "$SCROW_BOOT_DIR/installer"

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
# Download helper
# -----------------------------------------------------------------------------

# One curl attempt with bounded phases. On failure the partial output file is
# removed and the curl stderr is appended to the bootstrap log.
# $1 = url  $2 = output path  $3 = "4" to force IPv4, empty otherwise
scrow_curl_attempt() {
    local url="$1" out="$2" force4="$3" rc
    if [[ "$force4" == "4" ]]; then
        curl -4 -fsSL --proto '=https' --connect-timeout 15 --max-time 300 \
            --retry 3 --retry-delay 2 --retry-all-errors \
            -o "$out" "$url" 2>"${out}.err"
    else
        curl -fsSL --proto '=https' --connect-timeout 15 --max-time 300 \
            --retry 3 --retry-delay 2 --retry-all-errors \
            -o "$out" "$url" 2>"${out}.err"
    fi
    rc=$?
    if (( rc != 0 )); then
        rm -f "$out"
        scrow_boot_log "curl failed (exit $rc): $url"
        cat "${out}.err" >> "$SCROW_BOOT_LOG" 2>/dev/null || true
    fi
    rm -f "${out}.err"
    return "$rc"
}

# Fetch one installer file with an IPv4 fallback. Returns 0 on success.
scrow_fetch() {
    local url="$1" out="$2"
    local host="${url#https://}"
    host="${host%%/*}"
    if scrow_curl_attempt "$url" "$out" ""; then
        return 0
    fi
    scrow_curl_attempt "$url" "$out" "4"
}

# -----------------------------------------------------------------------------
# Progress
# -----------------------------------------------------------------------------

# Right-aligned, real percentage of the installer files fetched so far. The
# percentage advances only when a file has actually completed.
scrow_prepare_status() {
    local -i done=$1 total=$2
    local -i pct=$(( done * 100 / total ))
    local -i cols=80
    local got
    got="$(tput cols 2>/dev/null)"
    [[ "$got" =~ ^[0-9]+$ ]] && cols=$got
    (( cols < 40 )) && cols=40
    local -i padn=$(( cols - 18 - 4 ))
    local pad=""
    (( padn > 0 )) && printf -v pad '%*s' "$padn" ''
    printf '\rPreparing SCROW...%s%3d%%' "$pad" "$pct"
}

# -----------------------------------------------------------------------------
# Fetch the installer core
# -----------------------------------------------------------------------------

SCROW_BOOT_TOTAL=${#SCROW_CORE_FILES[@]}
SCROW_BOOT_DONE=0
for rel in "${SCROW_CORE_FILES[@]}"; do
    scrow_prepare_status "$SCROW_BOOT_DONE" "$SCROW_BOOT_TOTAL"
    SCROW_BOOT_TMP="$SCROW_BOOT_DIR/$rel.tmp"
    rm -f "$SCROW_BOOT_TMP"
    if ! scrow_fetch "$SCROW_RAW_URL/$rel" "$SCROW_BOOT_TMP"; then
        SCROW_BOOT_RC=$?
        rm -f "$SCROW_BOOT_TMP"
        printf '\r\033[K'
        SCROW_BOOT_HOST="${SCROW_RAW_URL#https://}"
        SCROW_BOOT_HOST="${SCROW_BOOT_HOST%%/*}"
        SCROW_BOOT_REASON="$(scrow_curl_reason "$SCROW_BOOT_RC" "$SCROW_BOOT_HOST")"
        scrow_boot_log "fetch failed: $SCROW_BOOT_REASON (url $SCROW_RAW_URL/$rel, curl exit $SCROW_BOOT_RC)"
        scrow_die "could not download installer file $rel — $SCROW_BOOT_REASON"
    fi
    mv -f "$SCROW_BOOT_TMP" "$SCROW_BOOT_DIR/$rel"
    SCROW_BOOT_DONE=$(( SCROW_BOOT_DONE + 1 ))
done
scrow_prepare_status "$SCROW_BOOT_DONE" "$SCROW_BOOT_TOTAL"
printf '\n'

# -----------------------------------------------------------------------------
# Verify + launch
# -----------------------------------------------------------------------------

SCROW_BOOT_OK=1
for rel in "${SCROW_CORE_FILES[@]}"; do
    if [[ ! -s "$SCROW_BOOT_DIR/$rel" ]]; then
        scrow_boot_log "missing or empty after fetch: $rel"
        SCROW_BOOT_OK=0
    fi
done
if (( SCROW_BOOT_OK == 0 )); then
    printf '\r\033[K'
    scrow_die "installer files are incomplete."
fi

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
