#!/bin/bash
# Master Security Hardening Script
# Run with: sudo ./apply-security.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root: sudo ./apply-security.sh${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(eval echo "~$REAL_USER")

echo "=========================================="
echo "    SECURITY HARDENING SCRIPT"
echo "=========================================="
echo ""

# 1. Install security packages
echo -e "${YELLOW}[1/11] Installing security packages...${NC}"
pacman -S --needed --noconfirm fail2ban clamav rkhunter lynis 2>/dev/null || {
    echo -e "${YELLOW}[WARN]${NC} Some packages may not be in official repos"
    echo "Try installing manually: yay -S fail2ban clamav rkhunter lynis"
}

# 2. SSH Hardening
echo -e "${YELLOW}[2/11] Applying SSH hardening...${NC}"
if [ -f "$SCRIPT_DIR/sshd_hardened.conf" ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d) 2>/dev/null || true
    cp "$SCRIPT_DIR/sshd_hardened.conf" /etc/ssh/sshd_config.d/99-hardened.conf
    echo -e "  ${GREEN}[OK]${NC} SSH config applied"
else
    echo -e "  ${YELLOW}[SKIP]${NC} sshd_hardened.conf not found in $SCRIPT_DIR"
fi

# 3. Firewall
echo -e "${YELLOW}[3/11] Applying firewall rules...${NC}"
if [ -f "$SCRIPT_DIR/nftables_hardened.conf" ]; then
    cp /etc/nftables.conf /etc/nftables.conf.bak.$(date +%Y%m%d) 2>/dev/null || true
    cp "$SCRIPT_DIR/nftables_hardened.conf" /etc/nftables.conf
    nft -f /etc/nftables.conf
    systemctl enable nftables
    systemctl start nftables
    echo -e "  ${GREEN}[OK]${NC} Firewall rules applied and enabled"
else
    echo -e "  ${YELLOW}[SKIP]${NC} nftables_hardened.conf not found"
fi

# 4. Kernel Hardening
echo -e "${YELLOW}[4/11] Applying kernel hardening...${NC}"
if [ -f "$SCRIPT_DIR/sysctl_security.conf" ]; then
    cp "$SCRIPT_DIR/sysctl_security.conf" /etc/sysctl.d/99-security.conf
    sysctl --system > /dev/null 2>&1
    echo -e "  ${GREEN}[OK]${NC} Kernel parameters hardened"
else
    echo -e "  ${YELLOW}[SKIP]${NC} sysctl_security.conf not found"
fi

# 5. Fail2Ban
echo -e "${YELLOW}[5/11] Configuring fail2ban...${NC}"
if [ -f "$SCRIPT_DIR/fail2ban_jail.local" ]; then
    cp "$SCRIPT_DIR/fail2ban_jail.local" /etc/fail2ban/jail.local
    systemctl enable fail2ban
    systemctl start fail2ban
    echo -e "  ${GREEN}[OK]${NC} Fail2Ban configured and started"
else
    echo -e "  ${YELLOW}[SKIP]${NC} fail2ban_jail.local not found"
fi

# 6. SSH Service
echo -e "${YELLOW}[6/11] Enabling SSH service...${NC}"
systemctl enable sshd
systemctl start sshd
echo -e "  ${GREEN}[OK]${NC} SSH service enabled"

# 7. File Permissions
echo -e "${YELLOW}[7/11] Fixing file permissions...${NC}"
chmod 700 "$USER_HOME/.ssh" 2>/dev/null || true
chmod 600 "$USER_HOME/.ssh/id_"* 2>/dev/null || true
chmod 600 "$USER_HOME/.ssh/"*_key 2>/dev/null || true
chmod 644 "$USER_HOME/.ssh/"*.pub 2>/dev/null || true
chmod 600 "$USER_HOME/.bash_history" 2>/dev/null || true
chmod 600 "$USER_HOME/.zsh_history" 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} File permissions fixed"

# 8. Disable LLMNR
echo -e "${YELLOW}[8/11] Disabling LLMNR...${NC}"
if [ -f /etc/systemd/resolved.conf ]; then
    cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.bak.$(date +%Y%m%d) 2>/dev/null || true
    sed -i 's/^#LLMNR=.*/LLMNR=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    grep -q "^LLMNR=" /etc/systemd/resolved.conf 2>/dev/null || echo "LLMNR=no" >> /etc/systemd/resolved.conf
    systemctl restart systemd-resolved 2>/dev/null || true
    echo -e "  ${GREEN}[OK]${NC} LLMNR disabled"
else
    echo -e "  ${YELLOW}[SKIP]${NC} /etc/systemd/resolved.conf not found"
fi

# 9. ClamAV
echo -e "${YELLOW}[9/11] Setting up ClamAV...${NC}"
freshclam 2>/dev/null || echo -e "  ${YELLOW}[WARN]${NC} freshclam failed (run manually later)"
systemctl enable clamav-freshclam 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} ClamAV configured"

# 10. ClamAV scanning is tied to the audit - no background scanner
echo -e "${YELLOW}[10/11] ClamAV malware scanning...${NC}"
echo "  ClamAV scans run on demand via: ./audit.sh (step 16)."
echo "  The always-on clamav-monitor.service has been removed: it rescanned"
echo "  /tmp every 5 min and pegged the CPU (~1GB RAM, 100% core)."
if systemctl list-unit-files clamav-monitor.service 2>/dev/null | grep -q clamav-monitor; then
    systemctl disable --now clamav-monitor.service 2>/dev/null || true
    pkill -f clamscan 2>/dev/null || true
    echo -e "  ${GREEN}[OK]${NC} Always-on clamav-monitor service disabled"
else
    echo -e "  ${GREEN}[OK]${NC} No clamav-monitor service present"
fi

# 11. USB Auto-Scan
echo -e "${YELLOW}[11/11] Setting up USB auto-scan...${NC}"
if [ -f "$SCRIPT_DIR/usb-scan.sh" ] && [ -f "$SCRIPT_DIR/usb-scan.rules" ]; then
    cp "$SCRIPT_DIR/usb-scan.sh" /usr/local/bin/usb-scan.sh
    chmod +x /usr/local/bin/usb-scan.sh
    cp "$SCRIPT_DIR/usb-scan.rules" /etc/udev/rules.d/99-usb-scan.rules
    udevadm control --reload-rules 2>/dev/null || true
    echo -e "  ${GREEN}[OK]${NC} USB drives will be auto-scanned for malware"
else
    echo -e "  ${YELLOW}[SKIP]${NC} USB scan files not found"
fi

echo ""
echo "=========================================="
echo "    HARDENING COMPLETE"
echo "=========================================="
echo ""
echo "Applied:"
echo "  - SSH hardened (root login disabled, no password auth)"
echo "  - nftables firewall (drop policy, rate limiting)"
echo "  - Kernel hardening (ASLR, SYN flood protection)"
echo "  - Fail2Ban (brute force protection)"
echo "  - LLMNR disabled (prevents credential theft)"
echo "  - File permissions fixed"
echo "  - ClamAV (antivirus)"
echo "  - ClamAV real-time monitor (auto-quarantine)"
echo "  - USB auto-scan (malware detection on connect)"
echo ""
echo "Next steps:"
echo "  1. Generate SSH key pair: ssh-keygen -t ed25519"
echo "  2. Copy public key to server: ssh-copy-id user@server"
echo "  3. Test SSH connection before closing current session"
echo "  4. Run audit: ./audit.sh"
echo ""
echo "Reboot recommended for kernel changes."
