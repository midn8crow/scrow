#!/usr/bin/env bash
# =============================================================================
# SCROW — engine (install / refresh / upgrade / repair / reset / remove)
# =============================================================================

# --- repository ---------------------------------------------------------------
# The repository is the single source of truth, and it is always a TEMPORARY
# clone. The one-line bootstrap clones the repository once into /tmp and runs
# install.sh from inside it; later `scrow` runs (from the installed engine
# bundle) clone it freshly whenever an operation needs it. There is no
# persistent local copy, no in-place merge and no second payload — the clone
# is removed when the process exits.
SCROW_REPO_TMP=""

# Validation-stage flags, set during an install run and summarized at the end
# so the final report only claims the stages that actually executed.
SCROW_STAGE_PACKAGES=0; SCROW_STAGE_CONFIG=0; SCROW_STAGE_SCRIPTS=0
SCROW_STAGE_SERVICES=0; SCROW_STAGE_PERMS=0; SCROW_STAGE_POST=0

scrow_repo_present() {
    [[ -d "$SCROW_REPO/.config" ]] && [[ -s "$SCROW_REPO/installer/scrow" ]] && [[ -s "$SCROW_REPO/VERSION" ]]
}

# After acquiring the repository, drive the whole operation from what the
# repository actually declares: refresh the version and the component
# definitions, and invalidate the hash caches (they were keyed on the old path).
scrow_repo_post_acquire() {
    local v
    v="$(cat "$SCROW_REPO/VERSION" 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$v" ]] && SCROW_VERSION="$v"
    if [[ -s "$SCROW_REPO/installer/components.sh" ]]; then
        source "$SCROW_REPO/installer/components.sh"
    fi
    SCROW_SHA_CACHE_LOADED=0
    SCROW_TARGET_SHA_LOADED=0
    scrow_log "repository acquired at $SCROW_REPO"
}

# Acquire the repository ONCE into a temporary directory via a shallow git
# clone. This is the single repository acquisition — there is no archive
# fallback and no second download. Fail-fast with the log path.
scrow_repo_acquire() {
    local tmp
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/scrow-XXXXXXXX" 2>/dev/null)" \
        || tmp="$(mktemp -d 2>/dev/null)"
    if [[ -z "$tmp" || ! -d "$tmp" ]]; then
        echo "  ${C_ERR}could not create a temporary directory for the repository.${C_RESET}"
        return 1
    fi
    # Track the temp dir from the START so the launcher's INT/TERM/cleanup
    # paths remove it even when acquisition is interrupted before success.
    SCROW_REPO_TMP="$tmp"

    echo "  ${C_DIM}Cloning SCROW repository…${C_RESET}"
    if ! scrow_run "clone repository" git clone --depth 1 --branch "$SCROW_REPO_BRANCH" \
        -- "$SCROW_REPO_URL" "$tmp/repo"; then
        scrow_repo_cleanup
        echo "  ${C_ERR}Could not clone the SCROW repository.${C_RESET}"
        echo "  ${C_DIM}Check the network and try again. Details: $SCROW_CURRENT_LOG${C_RESET}"
        return 1
    fi

    SCROW_REPO="$tmp/repo"
    if ! scrow_repo_present; then
        scrow_repo_cleanup
        echo "  ${C_ERR}The cloned SCROW repository is incomplete.${C_RESET}"
        echo "  ${C_DIM}Details: $SCROW_CURRENT_LOG${C_RESET}"
        return 1
    fi
    scrow_repo_post_acquire
    return 0
}

# Remove the temporary clone. Safe to call any number of times; the launcher
# calls it on every exit path so the clone never outlives the process.
scrow_repo_cleanup() {
    if [[ -n "$SCROW_REPO_TMP" && -d "$SCROW_REPO_TMP" ]]; then
        rm -rf "$SCROW_REPO_TMP" 2>/dev/null
    fi
    SCROW_REPO_TMP=""
}

# Defensive guard: ensure a valid repository is present, acquiring a temporary
# clone when the installer is running from the engine bundle. Fail loudly if
# the repository could not be obtained instead of pretending the component
# files exist.
scrow_repo_guard() {
    scrow_repo_present && return 0
    [[ -n "$SCROW_REPO_TMP" ]] && {
        echo "  ${C_ERR}SCROW repository is missing or incomplete at $SCROW_REPO.${C_RESET}"
        return 1
    }
    scrow_repo_acquire
}

# --- install -----------------------------------------------------------------
# Plan resolution: resolve the dependency graph ONCE into an ordered install
# plan (dependencies before dependents) so every component is processed exactly
# once — dependency installs are never repeated in the main loop.
declare -a SCROW_PLAN=()
declare -A SCROW_PLAN_SEEN=() SCROW_PLAN_STATUS=() SCROW_PLAN_REASON=()

scrow_plan_resolve() {
    SCROW_PLAN=()
    SCROW_PLAN_SEEN=()
    SCROW_PLAN_STATUS=()
    SCROW_PLAN_REASON=()
    local name
    for name in "$@"; do
        [[ -n "$name" ]] || continue
        scrow_plan_add "$name"
    done
}

scrow_plan_add() {
    local name="$1"
    [[ -n "${SCROW_PLAN_SEEN[$name]:-}" ]] && return 0
    SCROW_PLAN_SEEN[$name]=1
    if ! scrow_component_exists "$name"; then
        SCROW_PLAN_STATUS[$name]="failed"
        SCROW_PLAN_REASON[$name]="unknown component"
        echo "  ${C_WARN}Unknown component: $name${C_RESET}"
        return 0
    fi
    if scrow_config_component_skipped "$name"; then
        SCROW_PLAN_STATUS[$name]="skipped"
        SCROW_PLAN_REASON[$name]="disabled in config (COMPONENTS_SKIP)"
        return 0
    fi
    if scrow_component_installed "$name"; then
        SCROW_PLAN_STATUS[$name]="configured"
        SCROW_PLAN_REASON[$name]="already installed"
        return 0
    fi
    local dep
    for dep in $(scrow_component_needs "$name"); do
        scrow_plan_add "$dep"
    done
    SCROW_PLAN+=("$name")
    SCROW_PLAN_STATUS[$name]="pending"
}

# scrow_engine_install [names...]  (defaults to all uninstalled components)
scrow_engine_install() {
    local -a wanted=("$@")
    local -i full=0
    if [[ ${#wanted[@]} -eq 0 ]]; then
        local name
        for name in $(scrow_component_names); do
            scrow_config_component_skipped "$name" && continue
            scrow_component_installed "$name" || wanted+=("$name")
        done
        if [[ ${#wanted[@]} -eq 0 ]]; then
            # Everything is already present — nothing needs the repository.
            echo "  ${C_OK}Nothing to install — all components already present.${C_RESET}"
            return 0
        fi
        full=1
    else
        # A request is a "Full Installation" when it (together with what is
        # already configured) covers every available component — the TUI's
        # full-install screen only passes the uninstalled ones.
        local -i alln=0 cov=0
        local n2
        for n2 in $(scrow_component_names); do
            scrow_config_component_skipped "$n2" && continue
            alln+=1
            if scrow_component_installed "$n2"; then
                cov+=1
            else
                case " ${wanted[*]} " in
                    *" $n2 "*) cov+=1 ;;
                esac
            fi
        done
        (( alln > 0 && cov == alln )) && full=1
    fi

    # Acquire the temporary repository FIRST so the plan, the component
    # definitions and every deployed file come from the same source of truth.
    SCROW_STAGE_SEEN=()
    scrow_stage 1 "Repository preparation"
    scrow_repo_guard || return 1
    scrow_log "source: $SCROW_REPO"
    echo "  ${C_OK}Preparing installation… repository ✓${C_RESET}"
    echo "  ${C_DIM}  source: $SCROW_REPO${C_RESET}"

    scrow_stage 2 "System prerequisites"
    if ! command -v pacman >/dev/null 2>&1; then
        echo "  ${C_ERR}✗ pacman not found — SCROW requires Arch Linux.${C_RESET}"
        echo "  ${C_DIM}  Log: $SCROW_CURRENT_LOG${C_RESET}"
        return 1
    fi

    # On a Full Installation the repository IS the complete content: discover
    # what no component claims and record it so it is deployed and owned as
    # the "default" unit below.
    if (( full == 1 )); then
        scrow_state_set EXTRA "$(scrow_repo_unclaimed_units | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//')"
    fi

    scrow_stage 5 "Resolve selected components"
    scrow_plan_resolve "${wanted[@]}"

    local -a todo=()
    local name
    for name in "${SCROW_PLAN[@]}"; do todo+=("$name"); done

    if [[ ${#todo[@]} -eq 0 ]]; then
        # Nothing new to install. Converge any already-configured components
        # that were explicitly requested so a re-run stays in sync cheaply.
        local -i any=0 rc=0
        for name in "${wanted[@]}"; do
            if [[ "${SCROW_PLAN_STATUS[$name]:-}" == "configured" ]]; then
                scrow_converge_component "$name" || rc=1
                any=1
            fi
        done
        if (( full == 1 )); then
            scrow_converge_component default || rc=1
            any=1
        fi
        if (( any == 0 )); then
            echo "  ${C_OK}Nothing to install — all components already present.${C_RESET}"
            return 0
        fi
        return $rc
    fi

    echo
    echo "  ${C_ACCENT}SCROW Install${C_RESET}"
    echo "  ${C_DIM}Installing: ${todo[*]}${C_RESET}"
    echo

    if [[ " ${todo[*]} " == *" security "* ]]; then
        if [[ "${SCROW_APPLY_SECURITY:-0}" != "1" ]]; then
            echo "  ${C_WARN}Security hardening is opt-in and will be SKIPPED.${C_RESET}"
            echo "  ${C_DIM}Set APPLY_SECURITY=1 in ${SCROW_CONFIG_FILE} to apply the firewall, fail2ban and system hardening.${C_RESET}"
        else
            echo "  ${C_WARN}Security hardening IS enabled — firewall, fail2ban and system hardening will be applied.${C_RESET}"
        fi
        echo
    fi

    # paru is a GLOBAL prerequisite, not a per-component dependency. If any
    # planned component needs AUR packages, initialize it ONCE up front. If
    # that fails, the whole installation stops — never retry per component.
    local -i plan_has_aur=0
    local pname
    for pname in "${todo[@]}"; do
        [[ -n "$(scrow_component_aur "$pname")" ]] && plan_has_aur=1
    done
    if (( plan_has_aur == 1 )); then
        echo
        if ! scrow_ensure_paru; then
            echo
            echo "  ${C_ERR}✗ Full Installation FAILED${C_RESET}"
            echo "  ${C_ERR}✗ Failed to install paru${C_RESET}"
            echo "  ${C_DIM}  Required for AUR packages.${C_RESET}"
            echo "  ${C_DIM}  Log: $SCROW_CURRENT_LOG${C_RESET}"
            return 1
        fi
        echo
    fi

    scrow_backup_autobackup

    # Stage tracking for the final validation summary.
    SCROW_STAGE_PACKAGES=0; SCROW_STAGE_CONFIG=0; SCROW_STAGE_SCRIPTS=0
    SCROW_STAGE_SERVICES=0; SCROW_STAGE_PERMS=0; SCROW_STAGE_POST=0

    local -i failures=0
    for name in "${todo[@]}"; do
        scrow_install_component "$name" || failures+=1
    done

    # Keep explicitly-requested already-configured components in sync.
    for name in "${wanted[@]}"; do
        [[ "${SCROW_PLAN_STATUS[$name]:-}" == "configured" ]] || continue
        scrow_converge_component "$name" || failures+=1
    done

    # On a Full Installation, converge the unclaimed "default" content too.
    if (( full == 1 )); then
        if [[ -n "$(scrow_state_get EXTRA)" ]]; then
            scrow_converge_component default || failures+=1
            SCROW_STAGE_SCRIPTS=1
        fi
    fi

    if ! scrow_install_command; then
        SCROW_PLAN_STATUS[scrow]="failed"
        SCROW_PLAN_REASON[scrow]="command symlink failed"
        failures+=1
    fi

    local -i configured=0 skipped=0 failed_names=0 total=0
    local n
    local -a all_names=( "${wanted[@]}" )
    for n in "${todo[@]}"; do
        case " ${all_names[*]} " in *" $n "*) continue ;; esac
        all_names+=( "$n" )
    done
    for n in "${all_names[@]}"; do
        total+=1
        case "${SCROW_PLAN_STATUS[$n]:-}" in
            configured) configured+=1 ;;
            skipped)    skipped+=1 ;;
            failed)     failed_names+=1 ;;
        esac
    done
    (( failures > 0 )) && failed_names=$failures

    echo
    if (( failed_names > 0 )); then
        echo "  ${C_ERR}✗ Full Installation FAILED${C_RESET}"
        echo "  ${C_ERR}  ${configured}/${total} components configured${C_RESET}"
        echo "  ${C_ERR}  ${failed_names} failed:${C_RESET}"
        for n in "${all_names[@]}"; do
            [[ "${SCROW_PLAN_STATUS[$n]:-}" == "failed" ]] || continue
            echo "    ${C_ERR}✗ ${n} — ${SCROW_PLAN_REASON[$n]:-unknown reason}${C_RESET}"
        done
        [[ "${SCROW_PLAN_STATUS[scrow]:-}" == "failed" ]] && \
            echo "    ${C_ERR}✗ scrow — ${SCROW_PLAN_REASON[scrow]}${C_RESET}"
        (( skipped > 0 )) && {
            echo "  ${C_DIM}${skipped} skipped:${C_RESET}"
            for n in "${all_names[@]}"; do
                [[ "${SCROW_PLAN_STATUS[$n]:-}" == "skipped" ]] || continue
                echo "    ${C_DIM}− ${n} — ${SCROW_PLAN_REASON[$n]:-}${C_RESET}"
            done
        }
        echo "  ${C_DIM}Log: $SCROW_CURRENT_LOG${C_RESET}"
        return 1
    fi

    scrow_state_set INSTALLED 1
    scrow_state_set INSTALL_DATE "$(date '+%Y-%m-%d %H:%M:%S')"
    scrow_state_set SCROW_VERSION "$SCROW_VERSION"
    echo "  ${C_OK}${configured}/${total} components configured successfully${C_RESET}"
    if (( skipped > 0 )); then
        echo "  ${C_DIM}${skipped} skipped (optional post-install not enabled):${C_RESET}"
        for n in "${all_names[@]}"; do
            [[ "${SCROW_PLAN_STATUS[$n]:-}" == "skipped" ]] || continue
            echo "    ${C_DIM}− ${n} — ${SCROW_PLAN_REASON[$n]:-}${C_RESET}"
        done
    fi

    # Validation must confirm the REAL result before success is reported.
    echo
    echo "  ${C_ACCENT}Validating installation…${C_RESET}"
    scrow_stage 12 "Validate the resulting system"
    (( SCROW_STAGE_PACKAGES == 1 )) && echo "  ${C_OK}    ✓ Packages${C_RESET}"
    (( SCROW_STAGE_CONFIG == 1 ))   && echo "  ${C_OK}    ✓ Configurations${C_RESET}"
    (( SCROW_STAGE_SCRIPTS == 1 ))  && echo "  ${C_OK}    ✓ Scripts${C_RESET}"
    (( SCROW_STAGE_SERVICES == 1 )) && echo "  ${C_OK}    ✓ Services${C_RESET}"
    (( SCROW_STAGE_PERMS == 1 ))    && echo "  ${C_OK}    ✓ Permissions${C_RESET}"
    (( SCROW_STAGE_POST == 1 ))     && echo "  ${C_OK}    ✓ Post-install setup${C_RESET}"

    local -i vrc=0
    if (( plan_has_aur == 1 )) && ! scrow_paru_available; then
        echo "  ${C_ERR}    ✗ paru missing after installation${C_RESET}"
        vrc=1
    else
        echo "  ${C_OK}    ✓ paru present${C_RESET}"
    fi
    if [[ -f "$SCROW_STATE_FILE" ]]; then
        echo "  ${C_OK}    ✓ SCROW state: $SCROW_STATE_FILE${C_RESET}"
    else
        echo "  ${C_ERR}    ✗ SCROW state file missing: $SCROW_STATE_FILE${C_RESET}"
        vrc=1
    fi

    scrow_stage 13 "Cleanup temporary repository"
    scrow_repo_cleanup
    # The bootstrap's own clone (SCROW_REPO itself) is still live until the
    # launcher exits — anything else under /tmp/scrow-* is a leak.
    local leak
    leak="$(ls -d /tmp/scrow-* 2>/dev/null | grep -v -x "$SCROW_REPO" | head -1)"
    if [[ -n "$leak" ]]; then
        echo "  ${C_ERR}    ✗ leaked /tmp/scrow-* directory: $leak${C_RESET}"
        vrc=1
    else
        echo "  ${C_OK}    ✓ no leaked temporary repository${C_RESET}"
    fi

    if (( vrc != 0 )); then
        echo
        echo "  ${C_ERR}✗ Full Installation FAILED — validation${C_RESET}"
        echo "  ${C_DIM}  Log: $SCROW_CURRENT_LOG${C_RESET}"
        return 1
    fi
    echo "  ${C_OK}    ✓ installation validated${C_RESET}"
    echo "  ${C_OK}SCROW installation complete.${C_RESET}"
    echo "  ${C_DIM}Log: $SCROW_CURRENT_LOG${C_RESET}"
    return 0
}

# Install/refresh the installer ENGINE bundle — the code the installed `scrow`
# command runs. Code only, never payload: no configuration file is copied, so
# the repository stays the single source of truth for everything SCROW deploys.
scrow_engine_install_bundle() {
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] install engine bundle to $SCROW_ENGINE_DIR"
        return 0
    fi
    mkdir -p "$SCROW_ENGINE_DIR" || return 1
    local f
    for f in core state config backup sysd package components ownership engine menu; do
        cp -f "$SCROW_REPO/installer/$f.sh" "$SCROW_ENGINE_DIR/$f.sh" 2>/dev/null || return 1
    done
    cp -f "$SCROW_REPO/installer/scrow" "$SCROW_ENGINE_DIR/scrow" 2>/dev/null || return 1
    cp -f "$SCROW_REPO/install.sh" "$SCROW_ENGINE_DIR/install.sh" 2>/dev/null || return 1
    cp -f "$SCROW_REPO/bootstrap.sh" "$SCROW_ENGINE_DIR/bootstrap.sh" 2>/dev/null || return 1
    cp -f "$SCROW_REPO/VERSION" "$SCROW_ENGINE_DIR/VERSION" 2>/dev/null || return 1
    chmod +x "$SCROW_ENGINE_DIR/scrow"
    echo "  ${C_OK}scrow engine installed → $SCROW_ENGINE_DIR${C_RESET}"
}

# Make `scrow` available from anywhere: install the engine bundle and symlink
# the launcher into ~/.local/bin. The symlink points at the engine bundle (not
# the temporary repository), so the installed command keeps working after the
# repository clone is removed.
scrow_install_command() {
    scrow_engine_install_bundle || return 1
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] ln -sfn $SCROW_ENGINE_DIR/scrow $HOME/.local/bin/scrow"
        return 0
    fi
    mkdir -p "$HOME/.local/bin" 2>/dev/null || return 1
    ln -sfn "$SCROW_ENGINE_DIR/scrow" "$HOME/.local/bin/scrow" || return 1
    echo "  ${C_OK}scrow command installed → $HOME/.local/bin/scrow${C_RESET}"
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo "  ${C_DIM}Note: add $HOME/.local/bin to your PATH to run \`scrow\` from any directory.${C_RESET}"
    fi
}

# Install a single component: deps are already ordered by the plan, so this is
# strictly packages → deploy → ownership → post → validate. A component is only
# recorded as configured after EVERY required stage succeeds.
scrow_install_component() {
    local name="$1"
    local -i rc=0

    echo
    echo "  ${C_ACCENT}› ${name}${C_RESET}"
    SCROW_PLAN_STATUS[$name]="installing"

    scrow_need_root

    if ! scrow_install_packages "$name"; then
        scrow_fail_component "$name" "package installation failed"
        return 1
    fi
    SCROW_STAGE_PACKAGES=1
    echo "  ${C_OK}    ✓ packages${C_RESET}"

    # Scripts and user binaries are deployed with the utilities/default units.
    if [[ "$name" == "utilities" || "$name" == "default" ]]; then
        scrow_stage 9 "Deploy scripts & binaries"
        echo "  ${C_DIM}    Deploying scripts & binaries…${C_RESET}"
    fi
    echo "  ${C_DIM}    Deploying repository configuration…${C_RESET}"
    if ! scrow_deploy_component "$name"; then
        scrow_fail_component "$name" "configuration deployment failed"
        return 1
    fi
    if ! scrow_manifest_build "$name"; then
        scrow_fail_component "$name" "ownership recording failed"
        return 1
    fi
    SCROW_STAGE_CONFIG=1
    [[ "$name" == "utilities" ]] && SCROW_STAGE_SCRIPTS=1
    echo "  ${C_OK}    ✓ configuration${C_RESET}"

    SCROW_POST_SERVICES=0
    scrow_stage 11 "Run post-install hooks"
    scrow_component_post "$name"
    rc=$?
    if (( rc == 2 )); then
        SCROW_PLAN_STATUS[$name]="skipped"
        SCROW_PLAN_REASON[$name]="optional post-install not enabled"
        echo "  ${C_WARN}  − ${name} — skipped: optional post-install not enabled${C_RESET}"
        return 0
    elif (( rc != 0 )); then
        scrow_fail_component "$name" "post-install failed"
        scrow_manifest_remove_component "$name"
        return 1
    fi
    SCROW_STAGE_POST=1
    [[ "$name" == "utilities" ]] && SCROW_STAGE_PERMS=1
    (( SCROW_POST_SERVICES == 1 )) && SCROW_STAGE_SERVICES=1
    echo "  ${C_OK}    ✓ post-install${C_RESET}"
    (( SCROW_POST_SERVICES == 1 )) && echo "  ${C_OK}    ✓ services${C_RESET}"

    if ! scrow_component_validate "$name"; then
        scrow_fail_component "$name" "validation failed"
        scrow_manifest_remove_component "$name"
        return 1
    fi
    echo "  ${C_OK}    ✓ validation${C_RESET}"

    scrow_state_add_components "$name"
    scrow_log "installed component: $name"
    SCROW_PLAN_STATUS[$name]="configured"
    SCROW_PLAN_REASON[$name]=""
    return 0
}

scrow_fail_component() {
    local name="$1" reason="$2"
    SCROW_PLAN_STATUS[$name]="failed"
    SCROW_PLAN_REASON[$name]="$reason"
    echo "  ${C_ERR}✗ ${name} — ${reason}${C_RESET}"
    scrow_log "FAILED component: $name ($reason)"
}

# Install every declared package (official then AUR) for a component. Returns
# 1 as soon as a package installation fails — a component with missing
# packages is incomplete and must not be marked configured.
declare -A SCROW_PLAN_PKGS=()

scrow_install_packages() {
    local name="$1" pkg
    [[ -n "$(scrow_component_packages "$name")" ]] && scrow_stage 6 "Install official packages"
    [[ -n "$(scrow_component_aur "$name")" ]] && scrow_stage 7 "Install AUR packages using existing paru"
    for pkg in $(scrow_component_packages "$name"); do
        scrow_config_pkg_skipped "$pkg" && continue
        if [[ -n "${SCROW_PLAN_PKGS[$pkg]:-}" ]]; then
            continue
        fi
        scrow_pm_install "$pkg" || {
            echo "  ${C_ERR}      package installation failed: $pkg${C_RESET}"
            return 1
        }
        SCROW_PLAN_PKGS[$pkg]=1
    done
    for pkg in $(scrow_component_aur "$name"); do
        scrow_config_pkg_skipped "$pkg" && continue
        if [[ -n "${SCROW_PLAN_PKGS[$pkg]:-}" ]]; then
            continue
        fi
        scrow_pm_install "$pkg" || {
            echo "  ${C_ERR}      AUR package installation failed: $pkg${C_RESET}"
            return 1
        }
        SCROW_PLAN_PKGS[$pkg]=1
    done
}

# Validate that a component is actually complete on the system after
# deployment: every declared package installed, every declared path present,
# executable bits preserved from the repository, and SCROW's owned services
# enabled. Returns 1 when anything declared is missing.
scrow_component_validate() {
    local name="$1" p t f rel pkg svc
    local -i rc=0
    [[ "$SCROW_DRY_RUN" == "1" ]] && return 0

    for pkg in $(scrow_component_packages "$name") $(scrow_component_aur "$name"); do
        scrow_config_pkg_skipped "$pkg" && continue
        if ! scrow_pm_installed "$pkg"; then
            echo "  ${C_ERR}      missing package: $pkg${C_RESET}"
            rc=1
        fi
    done

    for p in $(scrow_component_paths "$name"); do
        [[ ! -e "$SCROW_REPO/$p" && ! -L "$SCROW_REPO/$p" ]] && continue
        t="$(scrow_target "$p")"
        if [[ -d "$SCROW_REPO/$p" ]]; then
            if [[ ! -d "$t" ]]; then
                echo "  ${C_ERR}      missing directory: $p${C_RESET}"
                rc=1
                continue
            fi
            while IFS= read -r f; do
                [[ -n "$f" ]] || continue
                rel="${f#$p/}"
                if [[ -e "$t/$rel" || -L "$t/$rel" ]]; then
                    if [[ -f "$SCROW_REPO/$f" && -x "$SCROW_REPO/$f" && ! -x "$t/$rel" ]]; then
                        echo "  ${C_ERR}      missing execute bit: $p/$rel${C_RESET}"
                        rc=1
                    fi
                else
                    echo "  ${C_ERR}      missing file: $p/$rel${C_RESET}"
                    rc=1
                fi
            done < <(scrow_repo_files "$p")
        elif [[ -L "$SCROW_REPO/$p" ]]; then
            [[ -L "$t" ]] || { echo "  ${C_ERR}      missing symlink: $p${C_RESET}"; rc=1; }
        else
            if [[ -e "$t" ]]; then
                if [[ -f "$SCROW_REPO/$p" && -x "$SCROW_REPO/$p" && ! -x "$t" ]]; then
                    echo "  ${C_ERR}      missing execute bit: $p${C_RESET}"
                    rc=1
                fi
            else
                echo "  ${C_ERR}      missing file: $p${C_RESET}"
                rc=1
            fi
        fi
    done

    for svc in $(scrow_state_services); do
        [[ -n "$svc" ]] || continue
        if ! scrow_service_is_enabled "$svc"; then
            echo "  ${C_ERR}      disabled service: $svc${C_RESET}"
            rc=1
        fi
    done
    return $rc
}

# Deploy any repo files of an already-configured component that are missing or
# out of sync with the repository. Never touches packages or services — used to
# converge configured components cheaply during re-install / update.
scrow_converge_component() {
    local name="$1" path full t
    local -i updated=0 rc=0
    for path in $(scrow_component_paths "$name"); do
        [[ ! -e "$SCROW_REPO/$path" && ! -L "$SCROW_REPO/$path" ]] && continue
        while IFS= read -r full; do
            [[ -n "$full" ]] || continue
            t="$(scrow_target "$full")"
            if [[ -L "$SCROW_REPO/$full" ]]; then
                [[ -L "$t" && "$(readlink "$t")" == "$(readlink "$SCROW_REPO/$full")" ]] && continue
            elif [[ -e "$t" ]]; then
                continue
            fi
            scrow_backup_existing "$full" "$name"
            scrow_deploy_path "$full" || rc=1
            updated+=1
        done < <(scrow_repo_files "$path")
    done
    (( updated > 0 )) && echo "  ${C_DIM}→ ${name}: ${updated} file(s) refreshed${C_RESET}"
    scrow_manifest_build "$name"
    return $rc
}

# --- refresh ---------------------------------------------------------------
# Re-check every managed file of the given components (default: all installed)
# and deploy any that are missing or changed since the manifest was written.
declare -A SCROW_SYNCED=()

# One pass over the manifest building a "already in sync" map, so the per-file
# refresh loop is a single associative lookup instead of re-parsing TSV rows.
# "In sync" is decided against what is LIVE on disk (current manifest hashes
# can be stale), so refresh actually re-deploys user-modified files.
scrow_build_synced_map() {
    SCROW_SYNCED=()
    local line rel src t
    scrow_target_sha_load
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        if [[ "${SCROW_MF[2]}" == "l" ]]; then
            t="$(scrow_target "$rel")"
            [[ -L "$t" && "$(readlink "$t" 2>/dev/null)" == "${SCROW_MF[3]}" ]] && SCROW_SYNCED["$rel"]=1
        else
            src="${SCROW_MF[3]#@}"
            [[ -z "$src" || "$src" == "${SCROW_MF[3]}" ]] && src="$rel"
            scrow_sha_cache_get "$src"
            t="$(scrow_target "$rel")"
            if [[ -n "$SCROW_SHA_CACHE_RET" && ! -L "$t" && -e "$t" ]]; then
                scrow_target_sha_get "$t"
                [[ "$SCROW_TARGET_SHA_RET" == "$SCROW_SHA_CACHE_RET" ]] && SCROW_SYNCED["$rel"]=1
            fi
        fi
    done < <(scrow_manifest_lines)
}

scrow_engine_refresh() {
    local -a names=("$@")
    [[ ${#names[@]} -eq 0 ]] && names=( $(scrow_owner_units) )
    echo
    echo "  ${C_ACCENT}SCROW Refresh${C_RESET}"
    echo "  ${C_DIM}Checking: ${names[*]}${C_RESET}"
    echo

    scrow_repo_guard || return 1

    scrow_backup_autobackup

    scrow_manifest_index_load
    scrow_sha_cache_load
    scrow_build_synced_map

    local name path
    local -i failed=0
    for name in "${names[@]}"; do
        [[ "$name" == "default" ]] || scrow_component_exists "$name" || { echo "  ${C_WARN}Unknown component: $name${C_RESET}"; continue; }
        echo "  ${C_ACCENT}› ${name}${C_RESET}"
        for path in $(scrow_component_paths "$name"); do
            [[ ! -e "$SCROW_REPO/$path" && ! -L "$SCROW_REPO/$path" ]] && continue
            scrow_refresh_path "$path" || failed=1
        done
    done
    scrow_manifest_rebuild "${names[@]}"
    echo
    if (( failed != 0 )); then
        echo "  ${C_ERR}Refresh did not complete — see the log.${C_RESET}"
        return 1
    fi
    echo "  ${C_OK}Refresh complete.${C_RESET}"
}

scrow_refresh_path() {
    local path="$1" file full
    local -a files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && files+=("$file")
    done < <(scrow_repo_files "$path")

    local -i updated=0 failed=0
    if [[ -d "$SCROW_REPO/$path" ]]; then
        for full in "${files[@]}"; do
            [[ -n "${SCROW_SYNCED[$full]:-}" ]] && continue
            updated+=1
            if [[ "$SCROW_DRY_RUN" == "1" ]]; then
                continue
            fi
            scrow_backup_existing "$full" "$(scrow_manifest_owner "$full")"
            scrow_deploy_path "$full" || failed=1
        done
    else
        [[ -n "${SCROW_SYNCED[$path]:-}" ]] && return 0
        updated=1
        [[ "$SCROW_DRY_RUN" == "1" ]] || {
            scrow_backup_existing "$path" ""
            scrow_deploy_path "$path" || failed=1
        }
    fi
    if (( updated > 0 )); then
        echo "  ${C_DIM}→ $path: $updated file(s) to update${C_RESET}"
    fi
    return $failed
}

scrow_manifest_owner() {
    local rel="$1" line
    line="${SCROW_MANIFEST_INDEX[$rel]:-}"
    if [[ -z "$line" ]]; then
        line="$(scrow_manifest_lines | awk -F'\t' -v p="$rel" '$1 == p { print; exit }')"
    fi
    [[ -n "$line" ]] && printf '%s' "${line##*$'\t'}"
}

# --- upgrade ----------------------------------------------------------------
# System packages, AUR, then rebuild the manifest (official hashes change).
scrow_engine_upgrade() {
    echo
    echo "  ${C_ACCENT}SCROW Upgrade${C_RESET}"
    [[ "$SCROW_DRY_RUN" == "1" ]] && { echo "  [dry-run] pacman -Syu + paru -Sua"; return 0; }
    scrow_repo_guard || return 1
    scrow_need_root
    scrow_run_sudo "system upgrade" pacman -Syu --noconfirm || return 1
    if command -v paru >/dev/null 2>&1; then
        scrow_run "aur upgrade" paru -Sua --noconfirm || return 1
    fi
    scrow_pm_cache
    echo "  ${C_DIM}Updating manifest hashes…${C_RESET}"
    scrow_manifest_rebuild
    echo
    echo "  ${C_OK}Upgrade complete.${C_RESET}"
}

# --- repair -----------------------------------------------------------------
# Restore the COMPLETE state of every installed component: missing packages,
# missing/modified/newly-added files, then re-run post-install (caches,
# generated config, services) for anything that changed. Reports failures
# instead of claiming success.
scrow_engine_repair() {
    echo
    echo "  ${C_ACCENT}SCROW Repair${C_RESET}"

    scrow_repo_guard || return 1
    scrow_backup_autobackup

    local -a names=( $(scrow_owner_units) )
    if [[ ${#names[@]} -eq 0 ]]; then
        echo "  ${C_WARN}Nothing installed to repair.${C_RESET}"
        return 0
    fi

    scrow_manifest_index_load
    scrow_sha_cache_load
    scrow_build_synced_map

    local name path full t
    local -i failed=0
    local prc

    # AUR packages need paru — ensure it ONCE up front, never per component.
    local -i repair_has_aur=0
    for name in "${names[@]}"; do
        [[ "$name" == "default" ]] && continue
        [[ -n "$(scrow_component_aur "$name")" ]] && repair_has_aur=1
    done
    if (( repair_has_aur == 1 )); then
        if ! scrow_ensure_paru; then
            echo "  ${C_ERR}✗ Full Installation FAILED${C_RESET}"
            echo "  ${C_ERR}✗ Failed to install paru${C_RESET}"
            echo "  ${C_DIM}  Required for AUR packages.${C_RESET}"
            return 1
        fi
    fi

    for name in "${names[@]}"; do
        [[ "$name" == "default" ]] || scrow_component_exists "$name" || { echo "  ${C_WARN}Unknown component: $name${C_RESET}"; continue; }
        echo "  ${C_ACCENT}› ${name}${C_RESET}"

        scrow_need_root

        echo "  ${C_DIM}  Checking packages…${C_RESET}"
        if ! scrow_install_packages "$name"; then
            echo "  ${C_ERR}  ✗ ${name} — package restoration failed${C_RESET}"
            failed=1
            continue
        fi

        local -i comp_changed=0
        for path in $(scrow_component_paths "$name"); do
            [[ ! -e "$SCROW_REPO/$path" && ! -L "$SCROW_REPO/$path" ]] && continue
            if [[ -d "$SCROW_REPO/$path" ]]; then
                while IFS= read -r full; do
                    [[ -n "$full" ]] || continue
                    [[ -n "${SCROW_SYNCED[$full]:-}" ]] && continue
                    comp_changed=1
                    [[ "$SCROW_DRY_RUN" == "1" ]] || {
                        scrow_backup_existing "$full" "$name"
                        scrow_deploy_path "$full" || failed=1
                    }
                done < <(scrow_repo_files "$path")
            else
                [[ -n "${SCROW_SYNCED[$path]:-}" ]] && continue
                comp_changed=1
                [[ "$SCROW_DRY_RUN" == "1" ]] || {
                    scrow_backup_existing "$path" "$name"
                    scrow_deploy_path "$path" || failed=1
                }
            fi
        done

        if (( comp_changed == 1 )); then
            echo "  ${C_DIM}  files restored — re-applying post-install…${C_RESET}"
            SCROW_POST_SERVICES=0
            scrow_component_post "$name"
            prc=$?
            if (( prc == 2 )); then
                echo "  ${C_WARN}  (skipped) optional post-install not enabled${C_RESET}"
            elif (( prc != 0 )); then
                echo "  ${C_ERR}  ✗ ${name} — post-install failed during repair${C_RESET}"
                failed=1
            fi
        fi
        scrow_manifest_build "$name"
    done

    echo "  ${C_DIM}Ensuring required services…${C_RESET}"
    scrow_services_apply || { echo "  ${C_ERR}service configuration failed${C_RESET}"; failed=1; }

    scrow_manifest_rebuild "${names[@]}"

    echo
    if (( failed != 0 )); then
        echo "  ${C_ERR}Repair did not complete — see the log.${C_RESET}"
        return 1
    fi
    echo "  ${C_OK}Repair complete — components are back to the official state.${C_RESET}"
}

# --- restore ----------------------------------------------------------------
# Restore managed files from an automatic backup (distinct from RESET, which
# removes everything, and REPAIR, which restores the official repo state).
scrow_engine_restore() {
    echo
    echo "  ${C_ACCENT}SCROW Restore (from backup)${C_RESET}"
    local -a backups=()
    local b
    while IFS= read -r b; do
        [[ -n "$b" ]] && backups+=("$b")
    done < <(scrow_backup_available)
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "  ${C_WARN}No automatic backups found in $(scrow_backup_dir)/AUTO_BACKUP.${C_RESET}"
        return 1
    fi

    # The restored manifest is rebuilt against the repository's expected
    # state, so a fresh clone is required.
    scrow_repo_guard || return 1
    echo
    echo "  ${C_DIM}Available backups (newest first):${C_RESET}"
    local -i i
    for i in "${!backups[@]}"; do
        printf '  %2d)  %s\n' "$((i + 1))" "${backups[$i]}"
    done
    echo
    local choice="${1:-}"
    if [[ -z "$choice" ]]; then
        read -r -p "  Restore which backup? [1-${#backups[@]}] " choice || choice="1"
    fi
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#backups[@]} )); then
        echo "  ${C_WARN}Invalid selection.${C_RESET}"
        return 1
    fi
    local ts="${backups[$((choice - 1))]}"
    local root
    root="$(scrow_backup_dir)/AUTO_BACKUP/$ts"
    echo "  ${C_DIM}Restoring from $ts …${C_RESET}"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] restore all files from $root"
        return 0
    fi
    [[ -f "$root/manifest" ]] || { echo "  ${C_WARN}Backup manifest missing in $root${C_RESET}"; return 1; }
    local line rel src dest
    local -i restored=0 failed=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        src="$root/$rel"
        [[ ! -e "$src" && ! -L "$src" ]] && continue
        dest="$(scrow_target "$rel")"
        mkdir -p "$(dirname "$dest")"
        scrow_backup_existing "$rel" "pre-restore"
        if [[ -L "$src" ]]; then
            rm -f "$dest"
            if ln -sfn "$(readlink "$src")" "$dest"; then
                restored+=1
            else
                echo "  ${C_ERR}  ✗ could not restore: $rel${C_RESET}"
                failed+=1
            fi
        elif [[ -d "$src" ]]; then
            if cp -a "$src"/. "$dest"/ 2>/dev/null; then
                restored+=1
            else
                echo "  ${C_ERR}  ✗ could not restore: $rel${C_RESET}"
                failed+=1
            fi
        else
            if cp -a "$src" "$dest" 2>/dev/null; then
                restored+=1
            else
                echo "  ${C_ERR}  ✗ could not restore: $rel${C_RESET}"
                failed+=1
            fi
        fi
    done < "$root/manifest"
    scrow_manifest_rebuild
    echo "  ${C_OK}Restored $restored file(s) from $ts.${C_RESET}"
    if (( failed > 0 )); then
        echo "  ${C_ERR}${failed} file(s) could not be restored.${C_RESET}"
        return 1
    fi
    return 0
}

# --- reset ------------------------------------------------------------------
# Disable SCROW services, remove every managed path, drop manifest & state.
scrow_engine_reset() {
    echo
    echo "  ${C_ACCENT}SCROW Reset${C_RESET}"
    if [[ "${SCROW_ASSUME_YES:-0}" != "1" ]]; then
        read -r -p "  Remove ALL SCROW-managed files and configuration? [y/N] " answer
        [[ "$answer" =~ ^[yY]$ ]] || { echo "  ${C_DIM}Aborted.${C_RESET}"; return 1; }
    fi

    scrow_backup_autobackup

    local line rel dest
    local -i failed=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        dest="$(scrow_target "$rel")"
        [[ ! -e "$dest" && ! -L "$dest" ]] && continue
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            echo "  [dry-run] remove: $rel"
        elif rm -rf "$dest" 2>/dev/null; then
            echo "  ${C_DIM}removed: $rel${C_RESET}"
        else
            echo "  ${C_ERR}  ✗ could not remove: $rel${C_RESET}"
            failed+=1
        fi
    done < <(scrow_manifest_lines)

    if [[ -L "$HOME/.local/bin/scrow" ]]; then
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            echo "  [dry-run] remove: $HOME/.local/bin/scrow"
        elif rm -f "$HOME/.local/bin/scrow"; then
            echo "  ${C_DIM}removed: $HOME/.local/bin/scrow${C_RESET}"
        else
            echo "  ${C_ERR}  ✗ could not remove: $HOME/.local/bin/scrow${C_RESET}"
            failed+=1
        fi
    fi

    # The installed engine bundle (code only) is SCROW-owned state too.
    if [[ -d "$SCROW_ENGINE_DIR" ]]; then
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            echo "  [dry-run] remove: $SCROW_ENGINE_DIR"
        elif rm -rf "$SCROW_ENGINE_DIR" 2>/dev/null; then
            echo "  ${C_DIM}removed: $SCROW_ENGINE_DIR${C_RESET}"
        else
            echo "  ${C_ERR}  ✗ could not remove: $SCROW_ENGINE_DIR${C_RESET}"
            failed+=1
        fi
    fi

    scrow_services_disable_owned
    scrow_manifest_clear
    scrow_state_set INSTALLED 0
    scrow_state_set COMPONENTS ""
    scrow_state_set SERVICES ""
    scrow_state_set EXTRA ""
    scrow_state_set INSTALL_DATE ""
    echo
    if (( failed > 0 )); then
        echo "  ${C_ERR}SCROW reset completed with ${failed} failure(s) removing files.${C_RESET}"
        return 1
    fi
    echo "  ${C_OK}SCROW reset complete.${C_RESET}"
    return 0
}

# --- remove component -------------------------------------------------------
scrow_engine_remove_component() {
    local name="$1"
    scrow_component_exists "$name" || { echo "  ${C_WARN}Unknown component: $name${C_RESET}"; return 1; }

    # The manifest rebuild below re-derives entries from the repository, so the
    # repository must be present — otherwise the whole manifest would be lost.
    scrow_repo_guard || return 1

    if [[ "${SCROW_ASSUME_YES:-0}" != "1" ]]; then
        read -r -p "  Remove component '$name' (files, not packages)? [y/N] " answer
        [[ "$answer" =~ ^[yY]$ ]] || { echo "  ${C_DIM}Aborted.${C_RESET}"; return 1; }
    fi

    scrow_backup_autobackup

    local line rel dest
    local -i failed=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        rel="${SCROW_MF[0]}"
        [[ "${SCROW_MF[6]}" != "$name" ]] && continue
        dest="$(scrow_target "$rel")"
        [[ ! -e "$dest" && ! -L "$dest" ]] && continue
        if [[ "$SCROW_DRY_RUN" == "1" ]]; then
            echo "  [dry-run] remove: $rel"
        elif rm -rf "$dest" 2>/dev/null; then
            echo "  ${C_DIM}removed: $rel${C_RESET}"
        else
            echo "  ${C_ERR}  ✗ could not remove: $rel${C_RESET}"
            failed+=1
        fi
    done < <(scrow_manifest_lines)

    scrow_manifest_rebuild
    scrow_state_remove_components "$name"
    echo
    if (( failed > 0 )); then
        echo "  ${C_ERR}Component '$name' removed with ${failed} failure(s).${C_RESET}"
        return 1
    fi
    echo "  ${C_OK}Component '$name' removed.${C_RESET}"
    return 0
}
