#!/usr/bin/env bash
# =============================================================================
# SCROW — entry point
# =============================================================================
# Thin launcher kept at the repository root so the one-line bootstrap and
# local clones can run `./install.sh`. All logic lives in installer/scrow and
# the installer/*.sh modules; this wrapper only needs to hand off to it.
# =============================================================================

set -uo pipefail

exec bash "$(cd "$(dirname "$0")" && pwd)/installer/scrow" "$@"
