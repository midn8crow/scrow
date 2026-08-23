#!/usr/bin/env bash
# =============================================================================
# SCROW — repair
# =============================================================================
# Validates deployment, then redeploys only MISSING or DIFFERENT files.

action_repair() {
    prevent_sudo_or_root

    printf "\n${C_BOLD}${C_CYN}  SCROW — Repair${C_RST}\n\n"

    if ! validate_deployment; then
        printf "\n${C_BOLD}  Redeploying broken/missing files…${C_RST}\n\n"

        local repo_file rel dest_file repaired=0
        while IFS= read -r repo_file; do
            rel="${repo_file#./}"
            dest_file="$HOME/$rel"

            # Deploy if missing or differs
            if [[ ! -e "$dest_file" ]] || \
               ( [[ -f "$repo_file" ]] && ! cmp -s "$repo_file" "$dest_file" 2>/dev/null ); then
                if [[ -d "$repo_file" ]]; then
                    deploy_home_dir "$repo_file" "$dest_file"
                elif [[ -f "$repo_file" ]]; then
                    mkdir -p "$(dirname "$dest_file")"
                    cp -a "$repo_file" "$dest_file" 2>/dev/null || true
                fi
                printf "${C_OK}  [ FIXED ]${C_RST} %s\n" "$rel"
                ((repaired++))
            fi
        done < <(find_deployable_files)

        set_permissions
        write_deploy_manifest

        printf "\n  Repaired %d files.\n" "$repaired"
    else
        printf "\n  Everything is in order. Nothing to repair.\n"
    fi
    printf "\n"
}
