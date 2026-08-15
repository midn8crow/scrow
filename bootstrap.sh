#!/usr/bin/env bash
# =============================================================================
# SCROW — one-line bootstrap (single stage)
# =============================================================================
# ONE source of truth: the SCROW repository itself. This script acquires the
# repository ONCE — a shallow git clone when git is available, otherwise a
# single archive download of the same repository — with real progress, then
# launches the installer directly from inside the repository. The repository
# is placed in a TEMPORARY directory (/tmp/scrow-XXXXXXXX) and removed when
# the installer exits. There is no persistent local copy and no second
# download stage.
#
#   curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash
#
# Environment overrides:
#   SCROW_BOOT_DIR       where the repository is acquired (default: a fresh
#                        /tmp/scrow-XXXXXXXX). If set explicitly and already
#                        holding a valid SCROW repository it is reused as-is.
#   SCROW_BOOT_BRANCH    branch to acquire (default: main)
#   SCROW_BOOT_LOG       where bootstrap diagnostics are logged (default:
#                        ~/.local/share/scrow/bootstrap.log)
#   SCROW_REPO_URL       git clone URL (default: https://github.com/midn8crow/scrow.git)
#   SCROW_TARBALL_URL    archive URL (default: the GitHub codeload tarball for
#                        SCROW_BOOT_BRANCH) — used only when git is unavailable.
# =============================================================================

set -uo pipefail

SCROW_BOOT_DIR="${SCROW_BOOT_DIR:-}"
SCROW_BOOT_BRANCH="${SCROW_BOOT_BRANCH:-main}"
SCROW_BOOT_LOG="${SCROW_BOOT_LOG:-$HOME/.local/share/scrow/bootstrap.log}"
SCROW_REPO_URL="${SCROW_REPO_URL:-https://github.com/midn8crow/scrow.git}"
SCROW_TARBALL_URL="${SCROW_TARBALL_URL:-https://codeload.github.com/midn8crow/scrow/tar.gz/refs/heads/$SCROW_BOOT_BRANCH}"

# Files/dirs that must exist after acquisition. Everything else in the
# repository is installed by the installer itself, guided by the manifest.
SCROW_BOOT_MARKERS=(
    install.sh
    VERSION
    installer/scrow
    installer/core.sh
)

printf 'SCROW · Arch Linux · Hyprland\n\n'

if ! command -v curl >/dev/null 2>&1; then
    printf 'SCROW: curl is required to download SCROW.\n' >&2
    exit 1
fi

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

# The repository lives in a TEMPORARY directory. Cleanup runs on EVERY exit
# path (including failure), but only for directories the bootstrap itself
# created — an explicitly provided SCROW_BOOT_DIR is the caller's and is
# reused across runs, never deleted.
SCROW_BOOT_CREATED=0
scrow_boot_cleanup() {
    if [[ "$SCROW_BOOT_CREATED" == "1" ]]; then
        rm -rf "$SCROW_BOOT_DIR" 2>/dev/null
    fi
}
scrow_boot_exit() {
    scrow_boot_cleanup
    exit $(( 128 + $1 ))
}
trap scrow_boot_cleanup EXIT
trap 'scrow_boot_exit 2' INT
trap 'scrow_boot_exit 15' TERM

# -----------------------------------------------------------------------------
# Repository acquisition (into a temporary directory)
# -----------------------------------------------------------------------------

# Stream stdin to stdout while rendering a single updating "Downloading SCROW
# repository…" percentage line. The percentage is real: bytes received / total
# length.
#
# Chunking goes through a temp file with a `wc -c` byte count — NOT through a
# bash variable and NOT via `while dd ...`:
#   - bash variables are C strings and silently drop NUL bytes, which would
#     corrupt the gzip archive.
#   - GNU dd returns 0 even on EOF (EOF is not an error), so `while dd ...`
#     would loop forever once the stream ends.
# A temp-file round-trip keeps the bytes intact and the loop bounded.
scrow_boot_progress() {
    local total="$1" label="$2"
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
            printf '\r\033[K%s %3d%%' "$label" "$(( done * 100 / total ))" >&2
        fi
        cat "$tmp"
        : > "$tmp"
    done
    printf '\r\033[K%s 100%%\n' "$label" >&2
}

# One download attempt with real progress and bounded phases. On failure the
# partial file is removed and curl's stderr is appended to the bootstrap log.
# $1 = url  $2 = output path  $3 = expected size (0 = unknown)  $4 = "4" for IPv4
scrow_curl_with_progress() {
    local url="$1" out="$2" total="$3" force4="$4" rc
    local -a curlopts=( -fL --proto '=https' --connect-timeout 15 --max-time 600 \
        --retry 3 --retry-delay 2 --retry-all-errors )
    [[ "$force4" == "4" ]] && curlopts+=( -4 )
    curl "${curlopts[@]}" -o - "$url" 2>"${out}.err" | scrow_boot_progress "$total" "Downloading SCROW repository..." > "$out"
    rc=${PIPESTATUS[0]}
    if (( rc != 0 )); then
        rm -f "$out"
        scrow_boot_log "curl failed (exit $rc): $url"
        cat "${out}.err" >> "$SCROW_BOOT_LOG" 2>/dev/null || true
    fi
    rm -f "${out}.err"
    return "$rc"
}

# Acquire the repository over HTTP(S) as a single archive, with an IPv4
# fallback. Returns 0 on success.
scrow_fetch_tarball() {
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

# Render git clone progress as one updating percentage line. Reads git's
# stderr, keeps the last NN% found in each line. Real progress: git only
# reports what it actually transferred.
scrow_boot_git_progress() {
    local pct line
    pct=0
    while IFS= read -r line; do
        if [[ "$line" =~ ([0-9]+)% ]]; then
            pct="${BASH_REMATCH[1]}"
            printf '\r\033[KDownloading SCROW repository... %3d%%' "$(( 10#$pct ))" >&2
        fi
    done
    printf '\r\033[KDownloading SCROW repository... 100%%\n' >&2
}

# A directory is a valid SCROW repository when it carries the markers the
# installer relies on.
scrow_boot_valid() {
    local dir="$1"
    [[ -d "$dir/.config" ]] && [[ -s "$dir/installer/scrow" ]] && [[ -s "$dir/VERSION" ]]
}

# Acquire the repository ONCE into the temporary directory. Reuses an
# explicitly provided SCROW_BOOT_DIR that already holds a valid repository
# (tests / unusual setups); otherwise a fresh /tmp/scrow-XXXXXXXX is created.
scrow_boot_acquire() {
    if [[ -n "$SCROW_BOOT_DIR" ]]; then
        if scrow_boot_valid "$SCROW_BOOT_DIR"; then
            scrow_boot_log "repository already present at $SCROW_BOOT_DIR"
            return 0
        fi
        if [[ -e "$SCROW_BOOT_DIR" ]]; then
            if [[ ! -d "$SCROW_BOOT_DIR" ]]; then
                scrow_die "$SCROW_BOOT_DIR exists but is not a directory. Move it away and retry."
            fi
            # An existing directory here is an incomplete acquisition from a
            # previous run (the valid state returns earlier) — clear it.
            rm -rf "$SCROW_BOOT_DIR"
        fi
    else
        SCROW_BOOT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/scrow-XXXXXXXX" 2>/dev/null)" \
            || SCROW_BOOT_DIR="$(mktemp -d 2>/dev/null)" \
            || SCROW_BOOT_DIR="${TMPDIR:-/tmp}/scrow.$$"
        SCROW_BOOT_CREATED=1
    fi

    # Clone/extract DIRECTLY into SCROW_BOOT_DIR — never through an
    # intermediate directory (a `mv dir/. dest/` merge fails with EBUSY on
    # some filesystems, and the intermediate is another thing that can leak).
    mkdir -p "$SCROW_BOOT_DIR"

    if command -v git >/dev/null 2>&1; then
        scrow_boot_log "cloning $SCROW_REPO_URL (branch $SCROW_BOOT_BRANCH)"
        git clone --depth 1 --branch "$SCROW_BOOT_BRANCH" --progress \
            "$SCROW_REPO_URL" "$SCROW_BOOT_DIR" 2> >(scrow_boot_git_progress)
        rc=${PIPESTATUS[0]}
        if (( rc == 0 )) && scrow_boot_valid "$SCROW_BOOT_DIR"; then
            scrow_boot_log "cloned into $SCROW_BOOT_DIR"
            return 0
        fi
        scrow_boot_log "git clone failed (exit $rc); falling back to the archive"
        # Clear the partial clone so the archive unpacks into a clean root.
        rm -rf "$SCROW_BOOT_DIR" 2>/dev/null
        mkdir -p "$SCROW_BOOT_DIR"
    fi

    local tmp archive
    tmp="$(mktemp -d 2>/dev/null)" || tmp="${TMPDIR:-/tmp}/scrow-acquire.$$"
    archive="$tmp/scrow.tar.gz"
    if ! scrow_fetch_tarball "$SCROW_TARBALL_URL" "$archive"; then
        rm -rf "$tmp"
        scrow_boot_log "fetch failed: $(scrow_curl_reason "$SCROW_BOOT_RC" "$SCROW_BOOT_HOST") (url $SCROW_TARBALL_URL, curl exit $SCROW_BOOT_RC)"
        scrow_die "could not download the SCROW repository — $(scrow_curl_reason "$SCROW_BOOT_RC" "$SCROW_BOOT_HOST")"
    fi

    if ! gzip -t "$archive" 2>/dev/null; then
        rm -rf "$tmp"
        scrow_boot_log "archive corrupt after download"
        scrow_die "the downloaded SCROW repository is incomplete or corrupt."
    fi

    # The GitHub tarball wraps everything in a single "<name>-<branch>/" dir;
    # --strip-components=1 unpacks it straight into the repository root.
    if ! tar -xzf "$archive" --strip-components=1 -C "$SCROW_BOOT_DIR"; then
        rm -rf "$tmp"
        scrow_boot_log "archive could not be unpacked"
        scrow_die "could not unpack the SCROW repository."
    fi
    rm -rf "$tmp"

    if ! scrow_boot_valid "$SCROW_BOOT_DIR"; then
        scrow_boot_log "no valid repository found in the archive"
        scrow_die "the downloaded SCROW repository is incomplete."
    fi
    scrow_boot_log "fetched archive into $SCROW_BOOT_DIR"
}

# -----------------------------------------------------------------------------
# Verify + launch
# -----------------------------------------------------------------------------

scrow_boot_acquire

SCROW_BOOT_OK=1
for rel in "${SCROW_BOOT_MARKERS[@]}"; do
    if [[ ! -s "$SCROW_BOOT_DIR/$rel" ]]; then
        scrow_boot_log "missing or empty after acquisition: $rel"
        SCROW_BOOT_OK=0
    fi
done
if (( SCROW_BOOT_OK == 0 )); then
    scrow_die "the SCROW repository is incomplete."
fi

printf 'Repository ready.\n'
printf 'Launching SCROW...\n\n'

# When run via `curl ... | bash`, bash's stdin is the curl pipe, which is
# already at EOF by the time the installer starts. The interactive TUI's
# `read` would then see EOF and exit immediately. Give the installer the
# user's actual terminal instead. The subshell probe actually tries to open
# /dev/tty, so headless/CI runs (no controlling terminal) fall through and
# keep their current stdin unchanged.
if [[ ! -t 0 ]] && ( : < /dev/tty ) 2>/dev/null; then
    bash "$SCROW_BOOT_DIR/install.sh" "$@" < /dev/tty
else
    bash "$SCROW_BOOT_DIR/install.sh" "$@"
fi
scrow_boot_rc=$?
exit $scrow_boot_rc
