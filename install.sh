#!/usr/bin/env bash
# =============================================================================
# SCROW — Arch Linux • Hyprland installer & dotfiles manager
# =============================================================================
# Entry point. Running ./install.sh (or `scrow`) opens the SCROW Manager.
# Command line options: --help, --version, --dry-run, --command <name>,
# --source <dir>. See scrow_print_help for details.
# =============================================================================

INSTALLER_DIR="$(cd "$(dirname "$0")" && pwd)"

# When launched via `curl … | bash`, stdin is the (already closed) curl pipe,
# not the terminal. Re-attach to the controlling terminal so the TUI stays
# usable and keyboard input works.
if [[ ! -t 0 ]]; then
    if ( exec 3< /dev/tty ) 2>/dev/null; then
        exec < /dev/tty
    fi
fi

# shellcheck disable=SC1090,SC1091
. "$INSTALLER_DIR/installer/core/lib.sh"
. "$INSTALLER_DIR/installer/ui/ui.sh"
. "$INSTALLER_DIR/installer/core/options.sh"
. "$INSTALLER_DIR/installer/manifest/components.sh"
. "$INSTALLER_DIR/installer/manifest/manifest.sh"
. "$INSTALLER_DIR/installer/backup/backup.sh"
. "$INSTALLER_DIR/installer/packages/manager.sh"
. "$INSTALLER_DIR/installer/hardware/gpu.sh"
. "$INSTALLER_DIR/installer/services/manager.sh"
. "$INSTALLER_DIR/installer/repository/git.sh"
. "$INSTALLER_DIR/installer/components/engine.sh"
. "$INSTALLER_DIR/installer/commands/operations.sh"
. "$INSTALLER_DIR/installer/commands/doctor.sh"
. "$INSTALLER_DIR/installer/commands/manager.sh"

ui_init

scrow_parse_args "$@"

scrow_log_init "$@"
scrow_state_init

if [[ -n "${SCROW_COMMAND:-}" ]]; then
    case "$SCROW_COMMAND" in
        full)       scrow_cmd_full ;;
        custom)     scrow_cmd_custom ;;
        components) scrow_cmd_components ;;
        update)     scrow_cmd_update ;;
        restore)    scrow_cmd_restore ;;
        reset)      scrow_cmd_reset ;;
        doctor)     scrow_cmd_doctor ;;
        uninstall)  scrow_cmd_uninstall ;;
        *)
            ui_error "Unknown command: $SCROW_COMMAND"
            scrow_print_help
            exit 1
            ;;
    esac
    exit $?
fi

scrow_cmd_manager
