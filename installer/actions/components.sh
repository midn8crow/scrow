#!/usr/bin/env bash
# =============================================================================
# SCROW — component installation
# =============================================================================
# Lets the user pick which components to deploy.

action_components() {
    prevent_sudo_or_root

    printf "\n${C_BOLD}${C_CYN}  SCROW — Component Selection${C_RST}\n\n"

    local components_file="$REPO_ROOT/installer/components.list"
    if [[ ! -f "$components_file" ]]; then
        printf "${C_ERR}  Error: components.list not found.${C_RST}\n"
        exit 1
    fi

    # Parse components
    local names=() descs=() pathsets=()
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        IFS='|' read -r name desc paths <<< "$line"
        names+=("$name")
        descs+=("$desc")
        pathsets+=("$paths")
    done < "$components_file"

    # Display menu
    printf "  Available components:\n\n"
    local i
    for i in "${!names[@]}"; do
        printf "    %2d) %-12s — %s\n" "$((i+1))" "${names[$i]}" "${descs[$i]}"
    done
    printf "\n"
    printf "  Enter numbers (space-separated), 'a' for all, or 'q' to cancel: "
    read -r choice

    [[ "$choice" == "q" || "$choice" == "Q" ]] && return 0

    local selected=()
    if [[ "$choice" == "a" || "$choice" == "A" ]]; then
        selected=("${!names[@]}")
    else
        for num in $choice; do
            if (( num >= 1 && num <= ${#names[@]} )); then
                selected+=("$((num-1))")
            fi
        done
    fi

    if (( ${#selected[@]} == 0 )); then
        printf "${C_WARN}  No components selected.${C_RST}\n"
        return 0
    fi

    # Ensure packages first
    printf "\n${C_BOLD}  Installing packages…${C_RST}\n\n"
    local -a official_pkgs aur_pkgs
    read_manifest "$REPO_ROOT/packages/official.txt" official_pkgs
    read_manifest "$REPO_ROOT/packages/aur.txt" aur_pkgs

    make_sudo_keepalive
    pacman_update
    ensure_paru
    resolve_conflicts
    install_official "${official_pkgs[@]}"
    install_aur "${aur_pkgs[@]}"
    stop_sudo_keepalive

    # Deploy selected components
    printf "\n${C_BOLD}  Deploying selected components…${C_RST}\n\n"
    local exclude_args=()
    local exc
    for exc in "${RSYNC_EXCLUDES[@]}"; do
        exclude_args+=(--exclude="$exc")
    done

    for idx in "${selected[@]}"; do
        printf "  ${C_BOLD}%s${C_RST} — %s\n" "${names[$idx]}" "${descs[$idx]}"
        local paths="${pathsets[$idx]}"
        local p
        for p in $paths; do
            if [[ ! -e "$REPO_ROOT/$p" ]]; then
                printf "${C_DIM}  [SKIP]${C_RST} %s (not in repo)\n" "$p"
                continue
            fi
            backup_file "$HOME/$p"
            if [[ -d "$REPO_ROOT/$p" ]]; then
                mkdir -p "$HOME/$p"
                rsync -a "${exclude_args[@]}" "$REPO_ROOT/$p/" "$HOME/$p/" 2>/dev/null || true
            elif [[ -f "$REPO_ROOT/$p" ]]; then
                mkdir -p "$(dirname "$HOME/$p")"
                cp -a "$REPO_ROOT/$p" "$HOME/$p" 2>/dev/null || true
            fi
            printf "${C_OK}  [ OK ]${C_RST} %s\n" "$p"
            record_deployed "$p"
        done
    done

    set_permissions
    try fc-cache -f
    write_deploy_manifest
    printf "\n"
}
