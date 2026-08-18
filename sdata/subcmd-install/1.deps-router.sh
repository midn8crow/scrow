#!/usr/bin/env bash
# =============================================================================
# SCROW — dependency router
# =============================================================================
# Routes to distro-specific dependency installation.

printf "${C_BOLD}  [1/3] Installing dependencies…${C_RST}\n"
printf "\n"

case "$SCROW_DISTRO_ID" in
    arch)
        # shellcheck source=../dist-arch/install-deps.sh
        source "$REPO_ROOT/sdata/dist-arch/install-deps.sh"
        ;;
    *)
        if [[ "$SCROW_DISTRO_FAMILY" == *"arch"* ]]; then
            # shellcheck source=../dist-arch/install-deps.sh
            source "$REPO_ROOT/sdata/dist-arch/install-deps.sh"
        else
            printf "${C_ERR}Error: Unsupported distribution: %s${C_RST}\n" "$SCROW_DISTRO_ID"
            printf "${C_ERR}SCROW currently only supports Arch Linux and Arch-based distros.${C_RST}\n"
            exit 1
        fi
        ;;
esac

printf "\n"
