#!/usr/bin/env bash
# =============================================================================
# SCROW - manifest engine
# =============================================================================
# The manifest is the record of exactly what SCROW owns. Every managed file,
# directory entry and symlink is tracked with checksums. SCROW never touches
# anything that is not listed in the manifest.
#
# Entry format (tab separated):
#   relpath  scope  type  link_target  official_sha  current_sha  component
#   scope : user | system   (system = deployed to /etc or /boot)
#   type  : f (file) | l (symlink)
# =============================================================================

# -----------------------------------------------------------------------------
# Path mapping
# -----------------------------------------------------------------------------
scrow_scope() {
    case "$1" in
        etc/*|boot/*) echo "system" ;;
        *) echo "user" ;;
    esac
}

scrow_target() {
    case "$1" in
        etc/*|boot/*) echo "/$1" ;;
        *) echo "$HOME/$1" ;;
    esac
}

# -----------------------------------------------------------------------------
# Repo file listing (git-aware, respects .gitignore)
# -----------------------------------------------------------------------------
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
scrow_manifest_exists() { [[ -s "$SCROW_MANIFEST" ]]; }

scrow_manifest_clear() {
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0
    : > "$SCROW_MANIFEST"
}

scrow_manifest_write_entry() {
    # scrow_manifest_write_entry <rel> <component> [source]
    # rel     : target path (relative; etc/*, boot/* are system scope)
    # source  : optional repo-relative path the file was deployed FROM (used for
    #           system files copied to non-matching locations, e.g.
    #           security-hardening/sshd_hardened.conf -> etc/ssh/...).
    # Idempotent: an existing entry for the same rel is replaced.
    local rel="$1" comp="$2" src_rel="${3:-}"
    local src dest scope type official current meta
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        return 0
    fi
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
    if [[ -f "$SCROW_MANIFEST" ]]; then
        awk -F'\t' -v r="$rel" '$1 != r' "$SCROW_MANIFEST" > "$SCROW_MANIFEST.tmp" 2>/dev/null
        mv -f "$SCROW_MANIFEST.tmp" "$SCROW_MANIFEST"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$scope" "$type" "$meta" "$official" "$current" "$comp" >> "$SCROW_MANIFEST"
}

# Register a system file deployed from a repo source to a different target.
scrow_manifest_write_deployed() {
    local target="$1" source="$2" comp="$3"
    local src
    src="$SCROW_REPO/$source"
    if [[ -e "$src" || -L "$src" ]]; then
        scrow_manifest_write_entry "$target" "$comp" "$source"
        scrow_log "manifest: deployed $source -> $target ($comp)"
    fi
}

scrow_manifest_source() {
    # Resolve the repo source path for a manifest line (first arg is the line).
    local line="$1" rel meta
    IFS=$'\t' read -r rel _scope _type meta _official _current _comp <<< "$line"
    if [[ "$meta" == @* ]]; then
        printf '%s' "${meta#@}"
    else
        printf '%s' "$rel"
    fi
}

scrow_manifest_build() {
    # scrow_manifest_build [component ...]   (defaults to all components)
    # Appends entries; use scrow_manifest_rebuild for a full regeneration.
    local comps=("$@")
    if [[ ${#comps[@]} -eq 0 ]]; then
        comps=( $(scrow_component_names) )
    fi
    local name paths p
    for name in "${comps[@]}"; do
        paths="$(scrow_component_paths "$name")"
        for p in $paths; do
            if [[ ! -e "$SCROW_REPO/$p" && ! -L "$SCROW_REPO/$p" ]]; then
                scrow_log "manifest: skip missing repo path $p"
                continue
            fi
            local file
            while IFS= read -r file; do
                [[ -n "$file" ]] && scrow_manifest_write_entry "$file" "$name"
            done < <(scrow_repo_files "$p")
        done
    done
}

# Full regeneration of the manifest. Captures and preserves deployed system
# entries (files copied from a repo source to a different location, e.g.
# security configs under /etc) which are not part of any component path.
scrow_manifest_rebuild() {
    # scrow_manifest_rebuild [component ...]  (defaults to installed components)
    local names=("$@")
    if [[ ${#names[@]} -eq 0 ]]; then
        names=( $(scrow_state_components) )
    fi
    local deployed=()
    local rel comp src
    while IFS=$'\t' read -r rel _scope type meta _official _current comp; do
        [[ -z "$rel" ]] && continue
        if [[ "$type" == "f" && "$meta" == @* ]]; then
            deployed+=("$rel|$comp|${meta#@}")
        fi
    done < <(scrow_manifest_lines)

    scrow_manifest_clear
    scrow_manifest_build "${names[@]}"

    local entry
    for entry in "${deployed[@]}"; do
        rel="${entry%%|*}"
        comp="${entry#*|}"; comp="${comp%%|*}"
        scrow_manifest_write_entry "$rel" "$comp" "${entry##*|}"
    done
    scrow_log "manifest rebuilt for: ${names[*]}"
}

# -----------------------------------------------------------------------------
# Manifest inspection
# -----------------------------------------------------------------------------
scrow_manifest_lines() { cat "$SCROW_MANIFEST" 2>/dev/null; }

# Print relpaths of manifest entries matching a predicate via callback.
scrow_manifest_entries() {
    # usage: scrow_manifest_entries [grep-pattern]
    local pat="${1:-.}"
    scrow_manifest_lines | awk -F'\t' -v p="$pat" '$1 ~ p'
}

# List files SCROW owns that differ from the current source repository state.
# Output: "relpath<tab>STATUS" where STATUS is MODIFIED or REMOVED-FROM-REPO.
scrow_manifest_out_of_sync() {
    local line
    while IFS=$'\t' read -r rel _scope type meta official current _comp; do
        [[ -z "$rel" ]] && continue
        if [[ "$type" == "f" ]]; then
            local src src_sha
            if [[ "$meta" == @* ]]; then
                src="${meta#@}"
            else
                src="$rel"
            fi
            src_sha="$(scrow_sha "$SCROW_REPO/$src" 2>/dev/null)"
            if [[ -z "$src_sha" ]]; then
                printf '%s\tREMOVED-FROM-REPO\n' "$rel"
            elif [[ "$current" != "$src_sha" ]]; then
                printf '%s\tMODIFIED\n' "$rel"
            fi
        fi
    done < <(scrow_manifest_lines)
}

# List manifest entries that differ from the manifest's own recorded official
# state (i.e. what was last deployed by SCROW).
scrow_manifest_modified() {
    local line
    while IFS=$'\t' read -r rel _scope type meta official current _comp; do
        [[ -z "$rel" ]] && continue
        case "$type" in
            l)
                [[ "$current" != "$meta" ]] && printf '%s\n' "$rel"
                ;;
            f)
                [[ "$current" != "$official" && "$current" != "missing" ]] && printf '%s\n' "$rel"
                ;;
        esac
    done < <(scrow_manifest_lines)
}

scrow_manifest_missing() {
    while IFS=$'\t' read -r rel _scope type _link _official current _comp; do
        [[ -z "$rel" ]] && continue
        [[ "$current" == "missing" ]] && printf '%s\n' "$rel"
    done < <(scrow_manifest_lines)
}

# Managed symlinks that are missing or point somewhere other than the official
# target recorded in the manifest.
scrow_manifest_broken_symlinks() {
    while IFS=$'\t' read -r rel _scope type meta _official current _comp; do
        [[ -z "$rel" ]] && continue
        [[ "$type" == "l" ]] || continue
        local target
        target="$(scrow_target "$rel")"
        if [[ ! -L "$target" || "$current" != "$meta" ]]; then
            printf '%s\n' "$rel"
        fi
    done < <(scrow_manifest_lines)
}

scrow_manifest_count() { scrow_manifest_lines | wc -l; }

# -----------------------------------------------------------------------------
# Deploy
# -----------------------------------------------------------------------------
scrow_deploy_path() {
    # Deploy one repo path to its target (user or system scope).
    local rel="$1" src dest target
    src="$SCROW_REPO/$rel"
    [[ ! -e "$src" && ! -L "$src" ]] && { scrow_log "deploy: missing source $rel"; return 1; }
    dest="$(scrow_target "$rel")"
    target="$(dirname "$dest")"

    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        if [[ -L "$src" ]]; then
            ui_dim "  [dry-run] link → $rel"
        elif [[ -d "$src" ]]; then
            ui_dim "  [dry-run] copy → $rel/ ($(scrow_repo_files "$rel" | wc -l) files)"
        else
            ui_dim "  [dry-run] copy → $rel"
        fi
        return 0
    fi

    if [[ -L "$src" ]]; then
        mkdir -p "$target"
        rm -f "$dest"
        ln -sfn "$(readlink "$src")" "$dest"
        scrow_log "deploy: link $rel -> $(readlink "$src")"
    elif [[ -d "$src" ]]; then
        mkdir -p "$dest"
        if [[ "$(scrow_scope "$rel")" == "system" ]]; then
            scrow_need_root
            scrow_log_tee "deploy $rel" sudo cp -a "$src"/. "$dest"/
        else
            scrow_log_tee "deploy $rel" cp -a "$src"/. "$dest"/
        fi
    else
        mkdir -p "$target"
        if [[ "$(scrow_scope "$rel")" == "system" ]]; then
            scrow_need_root
            scrow_log_tee "deploy $rel" sudo cp -a "$src" "$dest"
        else
            scrow_log_tee "deploy $rel" cp -a "$src" "$dest"
        fi
    fi
}

scrow_deploy_component() {
    # Deploy files for one component. Call scrow_manifest_rebuild afterwards.
    local name="$1" paths p
    paths="$(scrow_component_paths "$name")"
    for p in $paths; do
        scrow_deploy_path "$p"
    done
}

scrow_deploy_components() {
    local names=("$@") name
    for name in "${names[@]}"; do
        scrow_deploy_component "$name"
    done
}

# -----------------------------------------------------------------------------
# Ownership checks
# -----------------------------------------------------------------------------
scrow_manifest_owns() {
    # 0 if $1 (a $HOME-relative or /-relative path) is SCROW-managed
    local rel="$1" prefix
    case "$rel" in
        "$HOME/"*) prefix="${rel#"$HOME/"}" ;;
        "/"*)      prefix="${rel#/}" ;;
        *)         prefix="$rel" ;;
    esac
    scrow_manifest_lines | awk -F'\t' -v p="$prefix" '$1 == p { found=1 } END { exit !found }'
}
