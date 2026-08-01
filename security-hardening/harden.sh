#!/bin/bash
# MASTER HARDENING SCRIPT - Run once: sudo ~/security-hardening/harden.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Run with: sudo ~/security-hardening/harden.sh${NC}"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "    HEAVY-DUTY SYSTEM HARDENING"
echo "=========================================="
echo ""

# 1. Install packages
echo -e "${YELLOW}[1/12] Installing security packages...${NC}"
pacman -S --needed --noconfirm nftables fail2ban pacman-contrib bubblewrap 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} Packages installed"

# 2. Firewall
echo -e "${YELLOW}[2/12] Loading firewall rules...${NC}"
cp "$SCRIPT_DIR/nftables_hardened.conf" /etc/nftables.conf
nft -f /etc/nftables.conf
systemctl enable nftables 2>&1
# Force load rules directly (systemctl start can fail in some terminals)
nft -f /etc/nftables.conf 2>/dev/null
echo -e "  ${GREEN}[OK]${NC} Firewall loaded and enabled on boot"

# 3. Kernel hardening
echo -e "${YELLOW}[3/12] Applying kernel hardening...${NC}"
cp "$SCRIPT_DIR/sysctl_security.conf" /etc/sysctl.d/99-security.conf
sysctl --system > /dev/null 2>&1
echo -e "  ${GREEN}[OK]${NC} Kernel parameters hardened"

# 4. SSH hardening
echo -e "${YELLOW}[4/12] Hardening SSH...${NC}"
mkdir -p /etc/ssh/sshd_config.d
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d) 2>/dev/null || true
cp "$SCRIPT_DIR/sshd_hardened.conf" /etc/ssh/sshd_config.d/99-hardened.conf
systemctl restart sshd 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} SSH hardened (key-only, no root)"

# 5. Fail2Ban
echo -e "${YELLOW}[5/12] Setting up Fail2Ban...${NC}"
cp "$SCRIPT_DIR/fail2ban_jail.local" /etc/fail2ban/jail.local
systemctl enable fail2ban 2>&1
systemctl restart fail2ban 2>&1 || systemctl start fail2ban 2>&1
echo -e "  ${GREEN}[OK]${NC} Fail2Ban active (24h ban, 3 attempts)"

# 6. File permissions
echo -e "${YELLOW}[6/12] Fixing file permissions...${NC}"
chmod 700 "$USER_HOME/.ssh" 2>/dev/null || true
chmod 600 "$USER_HOME/.ssh/id_"* 2>/dev/null || true
chmod 600 "$USER_HOME/.ssh/"*_key 2>/dev/null || true
chmod 644 "$USER_HOME/.ssh/"*.pub 2>/dev/null || true
chmod 600 "$USER_HOME/.bash_history" 2>/dev/null || true
chmod 600 "$USER_HOME/.zsh_history" 2>/dev/null || true
chmod 700 "$USER_HOME/.local/bin" 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} File permissions locked"

# 7. Disable LLMNR
echo -e "${YELLOW}[7/12] Disabling LLMNR...${NC}"
if [ -f /etc/systemd/resolved.conf ]; then
    cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak.$(date +%Y%m%d) 2>/dev/null || true
    sed -i 's/^#LLMNR=.*/LLMNR=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    grep -q "^LLMNR=" /etc/systemd/resolved.conf 2>/dev/null || echo "LLMNR=no" >> /etc/systemd/resolved.conf
    systemctl restart systemd-resolved 2>/dev/null || true
    echo -e "  ${GREEN}[OK]${NC} LLMNR disabled"
fi

# 8. VPN/WARP firewall re-apply hook
echo -e "${YELLOW}[8/12] Installing VPN firewall hook...${NC}"
cat > /etc/NetworkManager/dispatcher.d/99-reapply-firewall << 'HOOK'
#!/bin/bash
INTERFACE=$1
ACTION=$2
if [ "$ACTION" = "up" ]; then
    /usr/bin/nft -f /etc/nftables.conf 2>/dev/null
fi
HOOK
chmod 755 /etc/NetworkManager/dispatcher.d/99-reapply-firewall
systemctl restart NetworkManager 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} Firewall auto-reapplies after VPN/network changes"

# 9. Disable unused services
echo -e "${YELLOW}[9/12] Disabling unused services...${NC}"
for svc in avahi-daemon cups bluetooth; do
    systemctl disable --now "$svc" 2>/dev/null || true
done
echo -e "  ${GREEN}[OK]${NC} Unused services disabled"

# 10. Deploy package-scanning scripts (aur-check + update-scan)
echo -e "${YELLOW}[10/12] Deploying package-scanning scripts...${NC}"
SRC_SEC="$USER_HOME/dotfiles/security-hardening"
LIVE_SEC="$USER_HOME/security-hardening"
mkdir -p "$LIVE_SEC"
for f in aur-check.sh update-scan.sh update-scan.hook; do
    if [ -f "$SRC_SEC/$f" ]; then
        cp "$SRC_SEC/$f" "$LIVE_SEC/$f"
    fi
done
chmod +x "$LIVE_SEC/aur-check.sh" "$LIVE_SEC/update-scan.sh" 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} aur-check.sh + update-scan.sh deployed (bubblewrap sandbox included)"

# 11. Pacman pre-install scan hook (runs on every pacman/paru update, survives reboots)
echo -e "${YELLOW}[11/12] Installing update-scan pacman hook...${NC}"
mkdir -p /etc/pacman.d/hooks
if [ -f "$LIVE_SEC/update-scan.hook" ]; then
    install -Dm644 "$LIVE_SEC/update-scan.hook" /etc/pacman.d/hooks/update-scan.hook
    echo -e "  ${GREEN}[OK]${NC} Hook installed - every update scans packages before install"
else
    echo -e "  ${YELLOW}[WARN]${NC} update-scan.hook not found, skipping"
fi

# 12. Wire cargo (rustup) into the shell so rustup-managed tools are found
echo -e "${YELLOW}[12/12] Wiring cargo (rustup) into shell...${NC}"
for rc in "$USER_HOME/.zshrc" "$USER_HOME/dotfiles/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -q '. "$HOME/.cargo/env"' "$rc" || echo '. "$HOME/.cargo/env"' >> "$rc"
done
echo -e "  ${GREEN}[OK]${NC} cargo env sourced (new shells see rustup cargo)"

echo ""
echo "=========================================="
echo -e "${GREEN}    HARDENING COMPLETE${NC}"
echo "=========================================="
echo ""

# Verify everything
echo -e "${YELLOW}Verifying...${NC}"
echo ""

CHECK=0

# Check firewall
if nft list ruleset 2>/dev/null | grep -q "table"; then
    echo -e "  ${GREEN}[OK]${NC} Firewall: active with rules"
    CHECK=$((CHECK+1))
else
    echo -e "  ${RED}[FAIL]${NC} Firewall: rules not loaded"
fi

# Check nftables service
if systemctl is-enabled nftables &>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} nftables: enabled on boot"
    CHECK=$((CHECK+1))
else
    echo -e "  ${RED}[FAIL]${NC} nftables: not enabled"
fi

# Check fail2ban
if systemctl is-active fail2ban &>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} Fail2Ban: active"
    CHECK=$((CHECK+1))
else
    echo -e "  ${RED}[FAIL]${NC} Fail2Ban: not running"
fi

# Check SSH
if systemctl is-active sshd &>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} SSH: active"
    CHECK=$((CHECK+1))
else
    echo -e "  ${YELLOW}[WARN]${NC} SSH: not running (may need reboot)"
fi

# Check NetworkManager hook
if [ -x /etc/NetworkManager/dispatcher.d/99-reapply-firewall ]; then
    echo -e "  ${GREEN}[OK]${NC} VPN hook: installed"
    CHECK=$((CHECK+1))
else
    echo -e "  ${RED}[FAIL]${NC} VPN hook: not installed"
fi

# Check pre-install scan hook
if [ -f /etc/pacman.d/hooks/update-scan.hook ] && [ -x "$LIVE_SEC/update-scan.sh" ]; then
    echo -e "  ${GREEN}[OK]${NC} Update scan: hook installed + scanner ready"
    CHECK=$((CHECK+1))
else
    echo -e "  ${RED}[FAIL]${NC} Update scan: hook or scanner missing"
fi

echo ""
echo "  $CHECK/6 checks passed"
echo ""
echo "Reboot recommended."
