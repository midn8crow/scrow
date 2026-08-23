# shellcheck shell=bash
# SCROW — 2. System setup (sourced by setup, not executed directly)

printf "${CYAN}[$0]: 2. System setup${RST}\n"

# ── User groups ────────────────────────────────────────────────────────────────

setup_groups() {
    local -a groups_needed=(video i2c input)
    for grp in "${groups_needed[@]}"; do
        if ! id -nG "$USER" 2>/dev/null | grep -qw "$grp"; then
            sudo groupadd -f "$grp"
            sudo usermod -aG "$grp" "$USER"
            printf "${GREEN}  [OK]${RST} Added user to group: $grp\n"
        fi
    done
}

# ── Kernel modules ─────────────────────────────────────────────────────────────

setup_modules() {
    local modules_dir="/etc/modules-load.d"
    sudo mkdir -p "$modules_dir"
    for mod in i2c-dev uinput; do
        echo "$mod" | sudo tee "$modules_dir/$mod.conf" >/dev/null
    done
}

# ── Services ───────────────────────────────────────────────────────────────────

setup_services() {
    # System services
    sudo systemctl enable --now sddm 2>/dev/null || true
    sudo systemctl enable --now NetworkManager 2>/dev/null || true
    sudo systemctl enable --now bluetooth 2>/dev/null || true

    # User services
    systemctl --user enable --now pipewire 2>/dev/null || true
    systemctl --user enable --now wireplumber 2>/dev/null || true
}

# ── Font cache ─────────────────────────────────────────────────────────────────

update_font_cache() {
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -fv 2>/dev/null || true
        printf "${GREEN}  [OK]${RST} Font cache updated\n"
    fi
}

# ── Run all setup steps ───────────────────────────────────────────────────────

setup_groups
setup_modules
setup_services
update_font_cache

printf "${GREEN}[$0]: System setup complete${RST}\n"
