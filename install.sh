#!/usr/bin/env bash
# =============================================================================
# SCROW — entry point
# =============================================================================
# Thin launcher kept at the repository root. It derives REPO_ROOT from its own
# location and hands off to installer/scrow, which treats that root as the
# single source of truth for the whole operation. The same file works
# identically from a local checkout and from bootstrap.sh's /tmp/scrow-XXXXXX
# clone.
# =============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export SCROW_REPO="$REPO_ROOT"

exec bash "$REPO_ROOT/installer/scrow" "$@"
