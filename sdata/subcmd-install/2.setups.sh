#!/usr/bin/env bash
# =============================================================================
# SCROW — system setup
# =============================================================================
# Configures systemd services, user groups, and system settings.

printf "${C_BOLD}  [2/3] System setup…${C_RST}\n"
printf "\n"

# ── User groups ───────────────────────────────────────────────────────────────
printf "  ${C_BOLD}User groups:${C_RST}\n"
for grp in video audio input optical storage; do
    if ! id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
        x "add user to group $grp" sudo usermod -aG "$grp" "$USER"
    else
        printf "${C_OK}  [ OK ]${C_RST} already in group %s\n" "$grp"
    fi
done

# ── Login shell ───────────────────────────────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}Login shell:${C_RST}\n"
if command -v zsh >/dev/null 2>&1; then
    local_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
    if [[ "$local_shell" != "$(command -v zsh)" ]]; then
        x "set default shell to zsh" bash -c "chsh -s $(command -v zsh)"
    else
        printf "${C_OK}  [ OK ]${C_RST} shell is already zsh\n"
    fi
else
    printf "${C_WARN}  [SKIP]${C_RST} zsh not found — skipping shell change\n"
fi

# ── Systemd user services ────────────────────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}Systemd user services:${C_RST}\n"
make_sudo_keepalive

# Core services to enable
services=(
    pipewire.service
    wireplumber.service
    mako.service
    waybar.service
    hyprland-session.target
    xdg-desktop-portal-hyprland.service
)

for svc in "${services[@]}"; do
    if systemctl --user is-enabled "$svc" >/dev/null 2>&1; then
        printf "${C_OK}  [ OK ]${C_RST} %s already enabled\n" "$svc"
    else
        x "enable $svc" systemctl --user enable "$svc" 2>/dev/null || true
    fi
done

# ── Systemd system services ──────────────────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}Systemd system services:${C_RST}\n"

# SDDM display manager
if command -v sddm >/dev/null 2>&1; then
    x "enable sddm" sudo systemctl enable sddm.service
fi

# NetworkManager
if command -v NetworkManager >/dev/null 2>&1; then
    x "enable NetworkManager" sudo systemctl enable NetworkManager.service
fi

# ── Loginctl linger ───────────────────────────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}Loginctl linger:${C_RST}\n"
if command -v loginctl >/dev/null 2>&1; then
    x "enable linger for $USER" sudo loginctl enable-linger "$USER" 2>/dev/null || true
fi

# ── Create required directories ───────────────────────────────────────────────
printf "\n"
printf "  ${C_BOLD}Directories:${C_RST}\n"
for dir in "$XDG_BIN_HOME" "$SCROW_BACKUP_DIR"; do
    if [[ ! -d "$dir" ]]; then
        x "create $(basename "$dir")" mkdir -p "$dir"
    fi
done

stop_sudo_keepalive
printf "\n"
