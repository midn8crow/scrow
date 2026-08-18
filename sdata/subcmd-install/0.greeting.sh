#!/usr/bin/env bash
# =============================================================================
# SCROW — greeting
# =============================================================================

printf "\n"
printf "${C_BOLD}${C_CYN}  ╔══════════════════════════════════════════════════╗${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ║                                                  ║${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ║   ███████╗████████╗██╗   ██╗████████╗██╗  ██╗   ║${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ║   ██╔════╝╚══██╔══╝██║   ██║╚══██╔══╝██║  ██║   ║${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ║   ███████╗   ██║   ██║   ██║   ██║   ███████║   ║${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ║   ╚════██║   ██║   ██║   ██║   ██║   ██╔══██║   ║${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ║   ███████║   ██║   ╚██████╔╝   ██║   ██║  ██║   ║${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ║   ╚══════╝   ╚═╝    ╚═════╝    ╚═╝   ╚═╝  ╚═╝   ║${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ║                                                  ║${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ║          Arch Linux · Hyprland · v%s${C_RST}            ${C_BOLD}${C_CYN}║${C_RST}\n" "$SCROW_VERSION"
printf "${C_BOLD}${C_CYN}  ║                                                  ║${C_RST}\n"
printf "${C_BOLD}${C_CYN}  ╚══════════════════════════════════════════════════╝${C_RST}\n"
printf "\n"
printf "${C_BOLD}  Welcome to SCROW!${C_RST}\n"
printf "  This installer will set up your Hyprland desktop.\n"
printf "\n"
printf "${C_DIM}  Distro: %s | Family: %s${C_RST}\n" "$SCROW_DISTRO_ID" "$SCROW_DISTRO_FAMILY"
printf "${C_DIM}  Repo:   %s${C_RST}\n" "$REPO_ROOT"
printf "\n"
