#!/bin/bash
# =============================================================================
# system-reset.sh - SCROW System Updates
# =============================================================================
# Used by the SCROW menu ("Scrow System Updates"). Instead of force-pulling
# and overwriting files, this dispatches to the SCROW installer / dotfiles
# manager, which handles automatic backups, the manifest, symlinks and
# verification itself:
#
#   Update from Backup  -> SCROW Restore  (return to an automatic backup)
#   Fetch from GitHub   -> SCROW Update   (update SCROW from the repository)
#
# No files are copied or removed here — the installer does that safely.
# =============================================================================

set -euo pipefail

HOME_DIR="$HOME"
STATE_DIR="$HOME_DIR/.local/share/scrow"
INSTALLER="$STATE_DIR/installer/install.sh"
SOURCE="$STATE_DIR/repo"

scrow_run() {
    local cmd="$1"

    if [[ -x "$INSTALLER" ]] && [[ -d "$SOURCE/.git" ]]; then
        exec bash "$INSTALLER" --source "$SOURCE" --command "$cmd"
    fi

    if [[ -x "$HOME_DIR/dotfiles/install.sh" ]]; then
        exec bash "$HOME_DIR/dotfiles/install.sh" --command "$cmd"
    fi

    if command -v scrow >/dev/null 2>&1; then
        exec scrow --command "$cmd"
    fi

    echo "SCROW is not installed."
    echo "Install it first:"
    echo "  curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash"
    exit 1
}

main() {
    case "${1:-}" in
        backup)
            scrow_run restore
            ;;
        github)
            scrow_run update
            ;;
        *)
            CHOICE=$(printf "Update from Backup\nFetch from GitHub\nBack" | fzf --prompt="Scrow System Updates > " --reverse --border --ansi)

            [ -z "$CHOICE" ] && exit 0
            [ "$CHOICE" = "Back" ] && exit 0

            case "$CHOICE" in
                "Update from Backup")
                    scrow_run restore
                    ;;
                "Fetch from GitHub")
                    scrow_run update
                    ;;
            esac
            ;;
    esac
}

main "$@"
