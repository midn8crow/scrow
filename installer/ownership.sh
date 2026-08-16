#!/usr/bin/env bash
# =============================================================================
# SCROW — ownership (manifest)
# =============================================================================
# The manifest records exactly what SCROW owns: every managed file, directory
# entry and symlink, with checksums and the owning component. SCROW never
# touches anything that is not listed here.
#
# Entry format (tab separated):
#   relpath  scope  type  link_target  official_sha  current_sha  component
#   scope : user | system   (system = deployed to /etc or /boot)
#   type  : f (file) | l (symlink)
#
# Format is stable — automatic backups made by earlier SCROW versions remain
# readable by this engine.
# =============================================================================

# -----------------------------------------------------------------------------
# Path mapping
# -----------------------------------------------------------------------------
scrow_scope() {
    case "$1" in
        etc/*|boot/*|usr/*) echo "system" ;;
        *) echo "user" ;;
    esac
}

scrow_target() {
    local t
    case "$1" in
        etc/*|boot/*|usr/*) t="/$1" ;;
        *) t="$HOME/$1" ;;
    esac
    # Test hook: redirect root-owned targets into a sandbox so a full
    # installation can be exercised without touching the real system.
    if [[ -n "${SCROW_TEST_SYSTEM_ROOT:-}" && "$t" == /* && "$t" != "$HOME"/* ]]; then
        printf '%s%s\n' "$SCROW_TEST_SYSTEM_ROOT" "$t"
        return 0
    fi
    printf '%s\n' "$t"
}

# List the files tracked by git for a repo-relative prefix (respects
# .gitignore); falls back to a plain find when there is no git repository.
scrow_repo_files() {
    local prefix="$1"
    if [[ -d "$SCROW_REPO/.git" ]]; then
        git -C "$SCROW_REPO" ls-files -- "$prefix" 2>/dev/null
    else
        if [[ -f "$SCROW_REPO/$prefix" || -L "$SCROW_REPO/$prefix" ]]; then
            printf '%s\n' "$prefix"
        elif [[ -d "$SCROW_REPO/$prefix" ]]; then
            find "$SCROW_REPO/$prefix" \( -type f -o -type l \) -print 2>/dev/null \
                | sed "s|^$SCROW_REPO/||"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Manifest I/O
# -----------------------------------------------------------------------------
# Split a TSV manifest line without collapsing empty fields (IFS tab handling
# would merge consecutive tabs). Result is placed in SCROW_MF, index 0..n.
declare -a SCROW_MF=()
scrow_tsv() {
    SCROW_MF=()
    local line="$1" rest f
    rest="$line"
    while :; do
        f="${rest%%$'\t'*}"
        SCROW_MF+=("$f")
        [[ "$rest" == *$'\t'* ]] || break
        rest="${rest#*$'\t'}"
    done
}

scrow_manifest_lines() { cat "$SCROW_MANIFEST" 2>/dev/null; }

# In-memory index of manifest lines by rel path (for hot loops).
declare -A SCROW_MANIFEST_INDEX=()
scrow_manifest_index_load() {
    SCROW_MANIFEST_INDEX=()
    local line rel
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        rel="${line%%$'\t'*}"
        SCROW_MANIFEST_INDEX["$rel"]="$line"
    done < <(scrow_manifest_lines)
}

scrow_manifest_clear() {
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0
    : > "$SCROW_MANIFEST"
}

# Register a single owned path.
#   scrow_manifest_entry <rel> <component> [source]
# rel    : target path, relative (etc/*, boot/* are system scope)
# source : optional repo-relative path the file was deployed FROM (used for
#          system files copied to non-matching locations).
scrow_manifest_entry() {
    local rel="$1" comp="$2" src_rel="${3:-}"
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0
    local src dest scope type meta official current
    src="$SCROW_REPO/$rel"
    dest="$(scrow_target "$rel")"
    scope="$(scrow_scope "$rel")"

    if [[ -L "$src" ]]; then
        type="l"
        meta="$(readlink "$src")"
        official="$meta"
    else
        type="f"
        if [[ -n "$src_rel" && "$src_rel" != "$rel" ]]; then
            meta="@$src_rel"
            official="$(scrow_sha "$SCROW_REPO/$src_rel")"
        else
            meta=""
            official="$(scrow_sha "$src")"
        fi
    fi

    if [[ -L "$dest" ]]; then
        current="$(readlink "$dest")"
    elif [[ -f "$dest" ]]; then
        current="$(scrow_sha "$dest")"
    else
        current="missing"
    fi

    # Replace any existing entry for the same path.
    if [[ -f "$SCROW_MANIFEST" ]]; then
        awk -F'\t' -v r="$rel" '$1 != r' "$SCROW_MANIFEST" > "$SCROW_MANIFEST.tmp" 2>/dev/null
        mv -f "$SCROW_MANIFEST.tmp" "$SCROW_MANIFEST"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rel" "$scope" "$type" "$meta" "$official" "$current" "$comp" >> "$SCROW_MANIFEST"
}

# Register a file deployed from a repo source to a different target.
scrow_manifest_deployed() {
    local target="$1" source="$2" comp="$3"
    [[ -e "$SCROW_REPO/$source" || -L "$SCROW_REPO/$source" ]] && scrow_manifest_entry "$target" "$comp" "$source"
}

# Build manifest entries for the given components (defaults to all).
scrow_manifest_build() {
    local comps=("$@")
    [[ ${#comps[@]} -eq 0 ]] && comps=( $(scrow_component_names) )
    local name paths p file
    for name in "${comps[@]}"; do
        paths="$(scrow_component_paths "$name")"
        for p in $paths; do
            [[ ! -e "$SCROW_REPO/$p" && ! -L "$SCROW_REPO/$p" ]] && continue
            while IFS= read -r file; do
                [[ -n "$file" ]] && scrow_manifest_entry "$file" "$name"
            done < <(scrow_repo_files "$p")
        done
    done
}

# Remove every manifest entry owned by a component. Used to roll back the
# manifest when a component fails to install completely, so SCROW never claims
# ownership of files that were never actually deployed.
scrow_manifest_remove_component() {
    local name="$1"
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0
    local line tmp
    tmp="$(mktemp)"
    local -i removed=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        if [[ "${SCROW_MF[6]:-}" != "$name" ]]; then
            printf '%s\n' "$line" >> "$tmp"
        else
            removed+=1
        fi
    done < <(scrow_manifest_lines)
    if (( removed > 0 )); then
        mv "$tmp" "$SCROW_MANIFEST"
        scrow_log "manifest rollback for failed component: $name ($removed entries)"
    else
        rm -f "$tmp"
    fi
}

# Full regeneration. Preserves deployed system entries (files copied from a
# repo source to a different location) that are not part of any component path.
scrow_manifest_rebuild() {
    local names=("$@")
    [[ ${#names[@]} -eq 0 ]] && names=( $(scrow_owner_units) )
    local deployed=()
    local line src comp
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        if [[ "${SCROW_MF[2]}" == "f" && "${SCROW_MF[3]}" == @* ]]; then
            deployed+=("${SCROW_MF[0]}|${SCROW_MF[6]}|${SCROW_MF[3]#@}")
        fi
    done < <(scrow_manifest_lines)

    scrow_manifest_clear
    scrow_manifest_build "${names[@]}"

    local entry
    for entry in "${deployed[@]}"; do
        rel="${entry%%|*}"
        comp="${entry#*|}"; comp="${comp%%|*}"
        scrow_manifest_entry "$rel" "$comp" "${entry##*|}"
    done
    scrow_log "manifest rebuilt for: ${names[*]}"
}

# -----------------------------------------------------------------------------
# Inspection
# -----------------------------------------------------------------------------
# Entries whose target differs from the current repository state, checked
# against what is LIVE on disk (not the manifest's last-known hash).
# Output: "relpath<tab>STATUS" (MODIFIED, REMOVED-FROM-REPO or BROKEN-LINK).
scrow_manifest_out_of_sync() {
    scrow_sha_cache_load
    scrow_target_sha_load
    local line rel src src_sha t t_status
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        if [[ "${SCROW_MF[2]}" == "l" ]]; then
            t="$(scrow_target "$rel")"
            if [[ ! -L "$t" || "$(readlink "$t" 2>/dev/null)" != "${SCROW_MF[3]}" ]]; then
                printf '%s\tBROKEN-LINK\n' "$rel"
            fi
            continue
        fi
        [[ "${SCROW_MF[2]}" == "f" ]] || continue
        src="${SCROW_MF[3]#@}"
        [[ -z "$src" || "$src" == "${SCROW_MF[3]}" ]] && src="$rel"
        scrow_sha_cache_get "$src"
        src_sha="$SCROW_SHA_CACHE_RET"
        if [[ -z "$src_sha" ]]; then
            printf '%s\tREMOVED-FROM-REPO\n' "$rel"
        else
            t="$(scrow_target "$rel")"
            if [[ -L "$t" || ! -e "$t" ]]; then
                printf '%s\tMODIFIED\n' "$rel"
            else
                scrow_target_sha_get "$t"
                t_status="$SCROW_TARGET_SHA_RET"
                [[ "$t_status" != "$src_sha" ]] && printf '%s\tMODIFIED\n' "$rel"
            fi
        fi
    done < <(scrow_manifest_lines)
}

# -----------------------------------------------------------------------------
# Deploy
# -----------------------------------------------------------------------------
# Deploy one repo path to its target (user or system scope). Returns 0 on
# success, 1 if the required directory creation or copy fails. System-scope
# targets (/etc, /boot, /usr) are created and written via sudo — never as the
# unprivileged user with the failure swallowed.
scrow_deploy_path() {
    local rel="$1" src dest target scope
    src="$SCROW_REPO/$rel"
    [[ ! -e "$src" && ! -L "$src" ]] && { scrow_log "deploy: missing source $rel"; return 1; }
    dest="$(scrow_target "$rel")"
    target="$(dirname "$dest")"
    scope="$(scrow_scope "$rel")"

    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        if [[ -L "$src" ]]; then
            echo "  [dry-run] link → $rel"
        elif [[ -d "$src" ]]; then
            echo "  [dry-run] copy → $rel/ ($(scrow_repo_files "$rel" | wc -l) files)"
        else
            echo "  [dry-run] copy → $rel"
        fi
        return 0
    fi

    if [[ -L "$src" ]]; then
        if [[ "$scope" == "system" ]]; then
            scrow_run_sudo "mkdir $rel" mkdir -p "$target" || return 1
        else
            mkdir -p "$target" 2>/dev/null || { scrow_log "deploy: mkdir failed $target"; return 1; }
        fi
        rm -f "$dest"
        ln -sfn "$(readlink "$src")" "$dest"
        scrow_log "deploy: link $rel -> $(readlink "$src")"
    elif [[ -d "$src" ]]; then
        if [[ "$scope" == "system" ]]; then
            scrow_run_sudo "mkdir $rel" mkdir -p "$dest" || return 1
            scrow_run_sudo "deploy $rel" cp -a "$src"/. "$dest"/ || return 1
        else
            mkdir -p "$dest" 2>/dev/null || { scrow_log "deploy: mkdir failed $dest"; return 1; }
            scrow_run "deploy $rel" cp -a "$src"/. "$dest"/ || return 1
        fi
        scrow_log "deploy: copy $rel/ → $dest/"
    else
        if [[ "$scope" == "system" ]]; then
            scrow_run_sudo "mkdir $rel" mkdir -p "$target" || return 1
            scrow_run_sudo "deploy $rel" cp -a "$src" "$dest" || return 1
        else
            mkdir -p "$target" 2>/dev/null || { scrow_log "deploy: mkdir failed $target"; return 1; }
            scrow_run "deploy $rel" cp -a "$src" "$dest" || return 1
        fi
        scrow_log "deploy: copy $rel → $dest"
    fi
}

scrow_deploy_component() {
    local name="$1" p
    local -i failed=0
    scrow_stage 7 "Deploy repository configuration"
    for p in $(scrow_component_paths "$name"); do
        if ! scrow_deploy_path "$p"; then
            echo "  ${C_ERR}      configuration deployment failed: $p${C_RESET}"
            failed=1
        fi
    done
    return $failed
}
