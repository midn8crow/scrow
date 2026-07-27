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
echo -e "${YELLOW}[1/9] Installing security packages...${NC}"
pacman -S --needed --noconfirm nftables fail2ban pacman-contrib 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} Packages installed"

# 2. Firewall
echo -e "${YELLOW}[2/9] Loading firewall rules...${NC}"
cp "$SCRIPT_DIR/nftables_hardened.conf" /etc/nftables.conf
nft -f /etc/nftables.conf
systemctl enable nftables 2>&1
# Force load rules directly (systemctl start can fail in some terminals)
nft -f /etc/nftables.conf 2>/dev/null
echo -e "  ${GREEN}[OK]${NC} Firewall loaded and enabled on boot"

# 3. Kernel hardening
echo -e "${YELLOW}[3/9] Applying kernel hardening...${NC}"
cp "$SCRIPT_DIR/sysctl_security.conf" /etc/sysctl.d/99-security.conf
sysctl --system > /dev/null 2>&1
echo -e "  ${GREEN}[OK]${NC} Kernel parameters hardened"

# 4. SSH hardening
echo -e "${YELLOW}[4/9] Hardening SSH...${NC}"
mkdir -p /etc/ssh/sshd_config.d
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d) 2>/dev/null || true
cp "$SCRIPT_DIR/sshd_hardened.conf" /etc/ssh/sshd_config.d/99-hardened.conf
systemctl restart sshd 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} SSH hardened (key-only, no root)"

# 5. Fail2Ban
echo -e "${YELLOW}[5/9] Setting up Fail2Ban...${NC}"
cp "$SCRIPT_DIR/fail2ban_jail.local" /etc/fail2ban/jail.local
systemctl enable fail2ban 2>&1
systemctl restart fail2ban 2>&1 || systemctl start fail2ban 2>&1
echo -e "  ${GREEN}[OK]${NC} Fail2Ban active (24h ban, 3 attempts)"

# 6. File permissions
echo -e "${YELLOW}[6/9] Fixing file permissions...${NC}"
chmod 700 "$USER_HOME/.ssh" 2>/dev/null || true
chmod 600 "$USER_HOME/.ssh/id_"* 2>/dev/null || true
chmod 600 "$USER_HOME/.ssh/"*_key 2>/dev/null || true
chmod 644 "$USER_HOME/.ssh/"*.pub 2>/dev/null || true
chmod 600 "$USER_HOME/.bash_history" 2>/dev/null || true
chmod 600 "$USER_HOME/.zsh_history" 2>/dev/null || true
chmod 700 "$USER_HOME/.local/bin" 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} File permissions locked"

# 7. Disable LLMNR
echo -e "${YELLOW}[7/9] Disabling LLMNR...${NC}"
if [ -f /etc/systemd/resolved.conf ]; then
    cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak.$(date +%Y%m%d) 2>/dev/null || true
    sed -i 's/^#LLMNR=.*/LLMNR=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    grep -q "^LLMNR=" /etc/systemd/resolved.conf 2>/dev/null || echo "LLMNR=no" >> /etc/systemd/resolved.conf
    systemctl restart systemd-resolved 2>/dev/null || true
    echo -e "  ${GREEN}[OK]${NC} LLMNR disabled"
fi

# 8. VPN/WARP firewall re-apply hook
echo -e "${YELLOW}[8/9] Installing VPN firewall hook...${NC}"
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
echo -e "${YELLOW}[9/9] Disabling unused services...${NC}"
for svc in avahi-daemon cups bluetooth; do
    systemctl disable --now "$svc" 2>/dev/null || true
done
echo -e "  ${GREEN}[OK]${NC} Unused services disabled"

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

echo ""
echo "  $CHECK/5 checks passed"
echo ""
echo "Reboot recommended."
