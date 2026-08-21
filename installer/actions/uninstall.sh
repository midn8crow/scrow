#!/usr/bin/env bash
# =============================================================================
# SCROW — uninstall
# =============================================================================
# Removes SCROW-deployed files using the deployment manifest.

action_uninstall() {
    printf "\n${C_BOLD}${C_CYN}  SCROW — Uninstall${C_RST}\n\n"

    if [[ ! -f "$SCROW_MANIFEST" ]]; then
        printf "${C_WARN}  No deployment manifest found.${C_RST}\n"
        printf "${C_WARN}  Cannot determine which files to remove.${C_RST}\n"
        return 0
    fi

    printf "  The following paths were deployed by SCROW:\n\n"
    local count=0
    while IFS= read -r path; do
        [[ -e "$HOME/$path" ]] && printf "    %s\n" "$path" && ((count++))
    done < "$SCROW_MANIFEST"

    if (( count == 0 )); then
        printf "${C_WARN}  No deployed files found.${C_RST}\n"
        return 0
    fi

    printf "\n  ${C_WARN}Remove all %d deployed paths? [y/N]${C_RST} " "$count"
    read -r confirm
    case "${confirm,,}" in
        y|yes)
            while IFS= read -r path; do
                local target="$HOME/$path"
                if [[ -e "$target" ]]; then
                    rm -rf "$target" 2>/dev/null && printf "  ${C_OK}removed${C_RST} %s\n" "$path"
                fi
            done < "$SCROW_MANIFEST"
            rm -f "$SCROW_MANIFEST"
            printf "\n  ${C_OK}Uninstall complete.${C_RST}\n\n"
            ;;
        *)
            printf "  Cancelled.\n\n"
            ;;
    esac
}
