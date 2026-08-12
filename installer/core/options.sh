#!/usr/bin/env bash
# =============================================================================
# SCROW - CLI option parsing
# =============================================================================
# Supports: --help --version --dry-run --manager --command <cmd> --source <dir>
# =============================================================================

scrow_print_help() {
    cat << EOF
SCROW $SCROW_VERSION — Arch Linux • Hyprland installer & dotfiles manager

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    --help               Show this help and exit.
    --version            Print the SCROW version and exit.
    --dry-run            Run in dry-run mode. Makes ZERO system changes;
                         shows what would be installed, deployed, symlinked,
                         backed up, serviced and changed.
    --manager            Open the SCROW Manager directly (default).
    --command <name>     Run a single command directly:
                         full | custom | components | update | restore |
                         reset | doctor | uninstall
    --source <dir>       Use <dir> as the SCROW source repository instead of
                         the default (used internally).

EXIT CODES:
    0  Success
    1  Error / cancelled operation

EXAMPLES:
    ./install.sh                      Open the SCROW Manager
    ./install.sh --dry-run            Preview a full installation
    ./install.sh --command doctor     Run Doctor / Repair directly
EOF
}

scrow_parse_args() {
    SCROW_COMMAND=""
    SCROW_MANAGER=1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                scrow_print_help
                exit 0
                ;;
            --version|-v)
                echo "SCROW v$SCROW_VERSION"
                exit 0
                ;;
            --dry-run)
                SCROW_DRY_RUN=1
                ;;
            --manager)
                SCROW_MANAGER=1
                ;;
            --command)
                shift
                SCROW_COMMAND="$1"
                SCROW_MANAGER=0
                ;;
            --source)
                shift
                SCROW_REPO="$(cd "$1" 2>/dev/null && pwd || echo "$1")"
                ;;
            *)
                ui_error "Unknown option: $1"
                scrow_print_help
                exit 1
                ;;
        esac
        shift
    done

    # SCROW_VERSION may have been resolved before --source overrode SCROW_REPO.
    SCROW_VERSION="$(cat "$SCROW_REPO/VERSION" 2>/dev/null | tr -d '[:space:]')"
    SCROW_VERSION="${SCROW_VERSION:-0.0.0}"

    export SCROW_COMMAND SCROW_MANAGER SCROW_DRY_RUN SCROW_REPO SCROW_VERSION
}
