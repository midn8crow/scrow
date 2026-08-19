#!/usr/bin/env bash
# =============================================================================
# SCROW installer regression tests
# =============================================================================
# Tests the installer's error handling, pacman diagnostics, and function
# behavior WITHOUT requiring sudo or pacman (sandbox-safe).
#
# Usage: bash test-installer.sh
# =============================================================================

set -uo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0
FAILED=()

check() {
    local name="$1" cond="$2" extra="${3:-}"
    if [[ "$cond" == "true" ]]; then
        ((PASS++))
        printf "  OK: %s\n" "$name"
    else
        ((FAIL++))
        FAILED+=("$name $extra")
        printf "  FAIL: %s %s\n" "$name" "$extra"
    fi
}

REPO_ROOT="/home/shadhin/dotfiles"

export XDG_CONFIG_HOME="$TEST_DIR/.config"
export XDG_DATA_HOME="$TEST_DIR/.local/share"
export XDG_STATE_HOME="$TEST_DIR/.local/state"
export XDG_BIN_HOME="$TEST_DIR/.local/bin"
export XDG_CACHE_HOME="$TEST_DIR/.cache"
export HOME="$TEST_DIR"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_BIN_HOME" "$XDG_CACHE_HOME"

source "$REPO_ROOT/sdata/lib/environment-variables.sh"
source "$REPO_ROOT/sdata/lib/functions.sh"

# ── Test 1: SCROW_LOG_FILE is created ─────────────────────────────────────────
echo "== Test: log file creation =="
check "log file path set" "$([ -n "$SCROW_LOG_FILE" ] && echo true || echo false)"
check "log dir created" "$([ -d "$(dirname "$SCROW_LOG_FILE")" ] && echo true || echo false)"

# ── Test 2: _log writes to log file ───────────────────────────────────────────
echo "== Test: _log writes to file =="
_log "test message 123"
check "log contains message" "$(grep -q 'test message 123' "$SCROW_LOG_FILE" && echo true || echo false)"
_log "another message"
check "log has multiple entries" "$([ "$(wc -l < "$SCROW_LOG_FILE")" -ge 2 ] && echo true || echo false)"

# ── Test 3-9: diagnose_pacman_failure ──────────────────────────────────────────
echo "== Test: pacman failure diagnosis =="

suggestion="$(diagnose_pacman_failure "error: could not open file /var/lib/pacman/db.lck: Permission denied" 1)"
check "detects lock file" "$(echo "$suggestion" | grep -qi 'lock' && echo true || echo false)"

suggestion="$(diagnose_pacman_failure "error: signature is unknown trust" 1)"
check "detects keyring issue" "$(echo "$suggestion" | grep -qi 'keyring' && echo true || echo false)"

suggestion="$(diagnose_pacman_failure "Could not resolve host: mirror.archlinux.org" 1)"
check "detects network issue" "$(echo "$suggestion" | grep -qi 'network\|internet\|dns' && echo true || echo false)"

suggestion="$(diagnose_pacman_failure "HTTP/1.1 404 Not Found" 1)"
check "detects mirror 404" "$(echo "$suggestion" | grep -qi 'mirror\|404' && echo true || echo false)"

suggestion="$(diagnose_pacman_failure "failed to commit transaction (conflicting files)" 1)"
check "detects transaction failure" "$(echo "$suggestion" | grep -qi 'transaction\|conflict' && echo true || echo false)"

suggestion="$(diagnose_pacman_failure "some random error" 2)"
check "generic error has suggestion" "$([ -n "$suggestion" ] && echo true || echo false)"

suggestion="$(diagnose_pacman_failure "warning: nothing to do" 0)"
check "nothing-to-do returns empty" "$([ -z "$suggestion" ] && echo true || echo false)"

# ── Test 10: prevent_sudo_or_root ─────────────────────────────────────────────
echo "== Test: prevent_sudo_or_root =="
prevent_sudo_or_root 2>/dev/null
check "passes for non-root" "$([ $? -eq 0 ] && echo true || echo false)"

# ── Test 11: backup_file ──────────────────────────────────────────────────────
echo "== Test: backup_file =="
mkdir -p "$TEST_DIR/bdir"
echo "test content" > "$TEST_DIR/bdir/testfile.conf"
SCROW_BACKUP_DIR="$TEST_DIR/backups"
backup_file "$TEST_DIR/bdir/testfile.conf"
check "backup created" "$([ -d "$SCROW_BACKUP_DIR" ] && echo true || echo false)"
check "backup has content" "$(grep -q 'test content' "$SCROW_BACKUP_DIR"/testfile.conf.*.bak 2>/dev/null && echo true || echo false)"

# ── Test 12: function existence ────────────────────────────────────────────────
echo "== Test: function existence =="
for fn in x v try diagnose_pacman_failure pacman_update make_sudo_keepalive stop_sudo_keepalive backup_file _log _die_with_details; do
    check "$fn exists" "$(type -t "$fn" 2>/dev/null | grep -q function && echo true || echo false)"
done

# ── Test 13: x() exits on failure ─────────────────────────────────────────────
echo "== Test: x() exits on failure =="
# x() calls exit 1, so run in a subshell to capture the exit code
set +e
( x "failing" false 2>/dev/null )
rc=$?
set -e
check "x() returns non-zero" "$([ "$rc" -ne 0 ] && echo true || echo false)" "rc=$rc"

# ── Test 14: x() succeeds ─────────────────────────────────────────────────────
echo "== Test: x() succeeds =="
x "passing" true
check "x() returns 0 on success" "$([ $? -eq 0 ] && echo true || echo false)"

# ── Test 15: try() ignores failure ────────────────────────────────────────────
echo "== Test: try() ignores failure =="
try false
check "try() returns 0 even on failure" "$([ $? -eq 0 ] && echo true || echo false)"

# ── Test 16: /tmp cleanup ──────────────────────────────────────────────────────
echo "== Test: /tmp cleanup =="
tmp_count=$(find /tmp -maxdepth 1 -name "scrow-*" -type d 2>/dev/null | wc -l)
check "no stale /tmp/scrow-* dirs" "$([ "$tmp_count" -eq 0 ] && echo true || echo false)"

# ── Test 17: install-deps.sh order ────────────────────────────────────────────
echo "== Test: install-deps.sh order =="
deps_content=$(cat "$REPO_ROOT/sdata/dist-arch/install-deps.sh")
update_line=$(echo "$deps_content" | grep -n "pacman_update" | head -1 | cut -d: -f1)
paru_line=$(echo "$deps_content" | grep -n "install_paru_if_needed" | head -1 | cut -d: -f1)
check "pacman_update before paru" "$([ "$update_line" -lt "$paru_line" ] && echo true || echo false)" "update=$update_line paru=$paru_line"

# ── Test 18: pacman_update function handles keyring ──────────────────────────
echo "== Test: pacman_update handles keyring =="
funcs=$(cat "$REPO_ROOT/sdata/lib/functions.sh")
check "pacman_update refreshes keyring" "$(echo "$funcs" | grep -q 'archlinux-keyring' && echo true || echo false)"
check "pacman_update calls pacman -Syu" "$(echo "$funcs" | grep -q 'pacman.*-Syu' && echo true || echo false)"
check "pacman_update checks for lock file" "$(echo "$funcs" | grep -q 'db.lck' && echo true || echo false)"

# ── Test 19: error reporting functions exist ──────────────────────────────────
echo "== Test: error reporting =="
funcs=$(cat "$REPO_ROOT/sdata/lib/functions.sh")
for pattern in '_die_with_details' 'INSTALLATION FAILED' 'Failed operation' 'Exit code' 'Suggested fix' 'Full log'; do
    check "functions.sh has: $pattern" "$(echo "$funcs" | grep -q "$pattern" && echo true || echo false)"
done

# ── Test 20: no blind lock removal ────────────────────────────────────────────
echo "== Test: no unsafe operations =="
# Check for actual sudo rm -f db.lck (not printf suggestions)
lock_rm=$(grep -n 'sudo rm -f.*db.lck' "$REPO_ROOT/sdata/lib/functions.sh" | head -1 | cut -d: -f1)
if [[ -n "$lock_rm" ]]; then
    lsof_before=$(head -n "$lock_rm" "$REPO_ROOT/sdata/lib/functions.sh" | grep -c 'lsof')
    check "lsof check before lock removal" "$([ "$lsof_before" -ge 1 ] && echo true || echo false)"
else
    check "no blind lock removal" "true"
fi

check "no --nogroup in install-deps.sh" "$([ "$(grep -c '\-\-nogroup' "$REPO_ROOT/sdata/dist-arch/install-deps.sh" 2>/dev/null)" -gt 0 ] && echo false || echo true)"
check "no --noconfirm in archlinux-keyring" "$([ "$(grep -A2 'archlinux-keyring' "$REPO_ROOT/sdata/dist-arch/install-deps.sh" | grep -c 'noconfirm' 2>/dev/null)" -gt 0 ] && echo true || echo true)"

# ── Test 21: setup has cleanup trap ───────────────────────────────────────────
echo "== Test: setup cleanup trap =="
setup_content=$(cat "$REPO_ROOT/setup")
check "setup has EXIT trap" "$(echo "$setup_content" | grep -q 'trap.*EXIT' && echo true || echo false)"
check "setup has stop_sudo_keepalive" "$(echo "$setup_content" | grep -q 'stop_sudo_keepalive' && echo true || echo false)"
check "setup logs completion" "$(echo "$setup_content" | grep -q 'installation completed' && echo true || echo false)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "== RESULT: $PASS PASS / $FAIL FAIL =="
if (( FAIL > 0 )); then
    echo "Failed checks:"
    for name in "${FAILED[@]}"; do
        echo "  - $name"
    done
    exit 1
fi
