#!/usr/bin/env bash
# =============================================================================
# SCROW — user configuration
# =============================================================================
# Optional overrides in ~/.config/scrow/config (KEY=VALUE lines, '#' comments):
#   BACKUP_DIR=        custom backup location
#   AUTO_BACKUP=0/1    disable automatic full backups before installs
#   SET_SHELL=0/1      change the login shell to zsh during install
#   APPLY_SECURITY=0/1 deploy system security hardening (requires root)
#   PKGS_SKIP=         space separated package names to never install
#   COMPONENTS_SKIP=   space separated component names to never offer
# =============================================================================

SCROW_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/scrow/config"

declare -A SCROW_CONFIG=()

scrow_config_load() {
    SCROW_CONFIG=()
    [[ -f "$SCROW_CONFIG_FILE" ]] || return 0
    local k v
    while IFS='=' read -r k v; do
        [[ -z "$k" || "$k" == \#* ]] && continue
        k="$(printf '%s' "$k" | tr -d ' ')"
        SCROW_CONFIG[$k]="$v"
    done < "$SCROW_CONFIG_FILE"

    [[ -n "${SCROW_CONFIG[BACKUP_DIR]:-}" ]]   && SCROW_BACKUP_CUSTOM="${SCROW_CONFIG[BACKUP_DIR]}"
    [[ -n "${SCROW_CONFIG[AUTO_BACKUP]:-}" ]]  && SCROW_AUTO_BACKUP="${SCROW_CONFIG[AUTO_BACKUP]}"
    [[ -n "${SCROW_CONFIG[SET_SHELL]:-}" ]]    && SCROW_SET_SHELL="${SCROW_CONFIG[SET_SHELL]}"
    [[ -n "${SCROW_CONFIG[APPLY_SECURITY]:-}" ]] && SCROW_APPLY_SECURITY="${SCROW_CONFIG[APPLY_SECURITY]}"
    scrow_log "config: loaded $SCROW_CONFIG_FILE"
}

scrow_config_pkg_skipped() {
    case " ${SCROW_CONFIG[PKGS_SKIP]:-} " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

scrow_config_component_skipped() {
    case " ${SCROW_CONFIG[COMPONENTS_SKIP]:-} " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}
