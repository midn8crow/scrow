#!/usr/bin/env bash
# =============================================================================
# SCROW — one-line bootstrap
# =============================================================================
# Downloads the SCROW repository and launches the installer. Uses curl + tar,
# so it works on a bare system that has no git yet (git is only needed later,
# and the installer installs it as part of the Utilities component).
#
#   curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash
#
# Environment overrides:
#   SCROW_BOOT_DIR       where the repository is fetched (default:
#                        ~/.local/share/scrow/bootstrap)
#   SCROW_BOOT_BRANCH    branch to fetch (default: main)
#   SCROW_REPO_URL       git URL to clone (default: the GitHub repository)
#   SCROW_TARBALL_URL    tarball URL to download (default: the GitHub archive)
#   SCROW_BOOT_LOG       where bootstrap diagnostics are logged (default:
#                        ~/.local/share/scrow/bootstrap.log)
# =============================================================================

set -uo pipefail

SCROW_BOOT_DIR="${SCROW_BOOT_DIR:-$HOME/.local/share/scrow/bootstrap}"
SCROW_BOOT_BRANCH="${SCROW_BOOT_BRANCH:-main}"
SCROW_REPO_URL="${SCROW_REPO_URL:-https://github.com/midn8crow/scrow.git}"
SCROW_TARBALL_URL="${SCROW_TARBALL_URL:-https://github.com/midn8crow/scrow/archive/refs/heads/$SCROW_BOOT_BRANCH.tar.gz}"
SCROW_BOOT_LOG="${SCROW_BOOT_LOG:-$HOME/.local/share/scrow/bootstrap.log}"

printf 'SCROW — Arch Linux • Hyprland\n'
printf 'Fetching SCROW installer…\n'

if ! command -v curl >/dev/null 2>&1; then
    printf 'SCROW: curl is required to download the installer.\n' >&2
    exit 1
fi

mkdir -p "$(dirname "$SCROW_BOOT_DIR")"

# Always start from a clean copy — never trust a stale/partial previous
# download (that is what previously caused phantom "check your connection"
# failures and broken re-installs).
rm -rf "$SCROW_BOOT_DIR"
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

# Download with internal retries and an IPv4 fallback. Returns 0 only after a
# complete, verified transfer; otherwise prints the reason to stderr.
scrow_download() {
    local url="$1" out="$2"
    local host="${url#https://}"
    host="${host%%/*}"

    local rc
    scrow_curl_attempt "$url" "$out" ""
    rc=$?
    if (( rc == 0 )); then
        return 0
    fi

    # DNS/connect/timeout failures (common under virtualized networking) are
    # retried over IPv4 only. IPv4 is not forced for the primary attempt.
    scrow_curl_attempt "$url" "$out" "4"
    rc=$?
    if (( rc == 0 )); then
        printf 'Note: reached %s over IPv4 after the first attempt failed.\n' "$host" >&2
        return 0
    fi

    local reason
    reason="$(scrow_curl_reason "$rc" "$host")"
    printf 'SCROW: %s\n' "$reason" >&2
    scrow_boot_log "download failed: $reason (curl exit $rc, url $url)"
    return 1
}

# -----------------------------------------------------------------------------
# Verify + unpack helper
# -----------------------------------------------------------------------------

# Verify the downloaded archive and unpack it. A partial/corrupt download is
# never passed to tar, and nothing that looks like a half-written installer is
# ever left behind.
scrow_unpack() {
    local archive="$1" dest="$2"

    if [[ ! -s "$archive" ]]; then
        printf 'SCROW: the downloaded installer was empty.\n' >&2
        scrow_boot_log "archive was empty: $archive"
        return 1
    fi
    if ! gzip -t "$archive" 2>/dev/null; then
        printf 'SCROW: the downloaded installer is incomplete or corrupt.\n' >&2
        scrow_boot_log "archive failed gzip integrity check: $archive"
        return 1
    fi
    if ! tar -xzf "$archive" --strip-components=1 -C "$dest"; then
        printf 'SCROW: could not unpack the downloaded installer.\n' >&2
        scrow_boot_log "tar extraction failed: $archive"
        return 1
    fi
    if [[ ! -f "$dest/install.sh" || ! -f "$dest/VERSION" ]]; then
        printf 'SCROW: the downloaded archive is missing expected files.\n' >&2
        scrow_boot_log "archive missing install.sh or VERSION: $archive"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Fetch the repository
# -----------------------------------------------------------------------------

got_repo=0
if command -v git >/dev/null 2>&1; then
    if git clone --depth 1 --branch "$SCROW_BOOT_BRANCH" "$SCROW_REPO_URL" "$SCROW_BOOT_DIR" 2>/dev/null; then
        got_repo=1
    else
        scrow_boot_log "git clone failed for $SCROW_REPO_URL; falling back to tarball"
        rm -rf "$SCROW_BOOT_DIR"
        mkdir -p "$SCROW_BOOT_DIR"
    fi
fi

if (( ! got_repo )); then
    # No git installed (or the git clone failed): fall back to a plain
    # tarball download, which only needs curl + tar.
    archive="$SCROW_BOOT_DIR/.scrow-bootstrap.tar.gz"
    if ! scrow_download "$SCROW_TARBALL_URL" "$archive"; then
        rm -rf "$SCROW_BOOT_DIR"
        scrow_die "could not download the SCROW installer."
    fi
    if ! scrow_unpack "$archive" "$SCROW_BOOT_DIR"; then
        rm -rf "$SCROW_BOOT_DIR"
        scrow_die "could not prepare the SCROW installer."
    fi
    rm -f "$archive"
fi

ver="$(cat "$SCROW_BOOT_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')"
if (( got_repo )) && [[ -n "$ver" ]] \
    && git -C "$SCROW_BOOT_DIR" rev-parse -q --verify "refs/tags/v$ver" >/dev/null 2>&1; then
    git -C "$SCROW_BOOT_DIR" checkout --quiet "v$ver" 2>/dev/null || true
    printf 'Using verified release v%s\n' "$ver"
else
    printf 'Using branch %s\n' "$SCROW_BOOT_BRANCH"
fi

printf 'Starting the SCROW Installer…\n\n'

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
