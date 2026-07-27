#!/bin/bash
# Security Audit Script - Detects malicious activity and misconfigurations

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
THREATS=0

threat() { echo -e "  ${RED}[THREAT]${NC} $1"; THREATS=$((THREATS+1)); }
warn()   { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
ok()     { echo -e "  ${GREEN}[OK]${NC} $1"; }
info()   { echo -e "  ${CYAN}[INFO]${NC} $1"; }

echo "=========================================="
echo "       SECURITY AUDIT REPORT"
echo "  $(date)"
echo "=========================================="
echo ""

# 1. Shell profile backdoors
echo -e "${YELLOW}[1] Checking shell profiles for backdoors...${NC}"
for rc in ~/.bashrc ~/.zshrc ~/.bash_profile ~/.zsh_profile ~/.profile; do
    [ -f "$rc" ] || continue
    SUSPICIOUS_LINES=$(grep -niE "curl.*\|.*sh|wget.*\|.*sh|base64.*-d.*\|.*sh|nc -[el]|/dev/tcp|python.*socket|nohup.*&" "$rc" 2>/dev/null | grep -viE "dircolors|compinit|promptinit|zinit|zplug|antibody|antigen|sheldon")
    if [ -n "$SUSPICIOUS_LINES" ]; then
        threat "Suspicious commands found in $rc"
        echo "$SUSPICIOUS_LINES" | head -5 | while IFS= read -r line; do echo "      $line"; done
    else
        ok "$rc - clean"
    fi
    if grep -qiE "bash -i.*>&.*|mkfifo.*nc|telnet.*\|.*sh" "$rc" 2>/dev/null; then
        threat "Possible reverse shell in $rc"
    fi
done
echo ""

# 2. SSH config
echo -e "${YELLOW}[2] Checking SSH configuration...${NC}"
if [ -f ~/.ssh/config ]; then
    if grep -qiE "ProxyCommand.*nc|RemoteCommand" ~/.ssh/config 2>/dev/null; then
        warn "SSH proxy/remote command found in ~/.ssh/config"
    else
        ok "~/.ssh/config - clean"
    fi
fi
if [ -f /etc/ssh/sshd_config ]; then
    PERMIT_ROOT=$(grep -i "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    PASS_AUTH=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ "$PERMIT_ROOT" = "yes" ]; then
        threat "SSH root login enabled"
    else
        ok "SSH root login: ${PERMIT_ROOT:-default}"
    fi
    if [ "$PASS_AUTH" != "no" ]; then
        warn "SSH password auth: ${PASS_AUTH:-yes} (should be 'no')"
    else
        ok "SSH password auth: disabled"
    fi
else
    info "No sshd_config found"
fi
echo ""

# 3. SUID/SGID binaries
echo -e "${YELLOW}[3] Checking for suspicious SUID/SGID binaries...${NC}"
KNOWN_SUID=(
    /usr/bin/sudo /usr/bin/su /usr/bin/passwd /usr/bin/chsh /usr/bin/newgrp
    /usr/bin/gpasswd /usr/bin/mount /usr/bin/umount /usr/bin/chfn /usr/bin/chage
    /usr/bin/write /usr/bin/sg /usr/bin/wall /usr/bin/expiry /usr/bin/ksu
    /usr/bin/unix_chkpwd /usr/bin/crontab /usr/bin/at /usr/bin/pkexec
    /usr/bin/fusermount /usr/bin/fusermount3 /usr/bin/socket
    /usr/lib/openssh/ssh-keysign /usr/lib/ssh/ssh-keysign
    /usr/lib/polkit-1/polkit-agent-helper-1
    /usr/lib/Xorg.wrap /usr/lib/dbus-daemon-launch-helper
    /usr/lib/electron*/chrome-sandbox /usr/lib/libgtop/libgtop_server2
    /usr/lib/polkit-1/polkit-agent-helper-1
)
SUID_FOUND=$(find /usr/bin /usr/sbin /usr/lib /usr/local/bin -maxdepth 2 -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null)
UNUSUAL_SUID=""
while IFS= read -r f; do
    [ -z "$f" ] && continue
    FOUND=false
    for known in "${KNOWN_SUID[@]}"; do
        if [ "$f" = "$known" ] 2>/dev/null; then FOUND=true; break; fi
        # Handle glob-like patterns for electron versions
        KNOWN_BASE=$(echo "$known" | sed 's/\*/[^/]*//')
        echo "$f" | grep -qE "^${KNOWN_BASE}$" 2>/dev/null && { FOUND=true; break; }
    done
    [ "$FOUND" = false ] && UNUSUAL_SUID="$UNUSUAL_SUID $f"
done <<< "$SUID_FOUND"
if [ -n "$UNUSUAL_SUID" ]; then
    threat "Unknown SUID/SGID binaries found:"
    for f in $UNUSUAL_SUID; do echo "      $f"; done
else
    ok "No unusual SUID/SGID binaries"
fi
echo ""

# 4. Malicious processes
echo -e "${YELLOW}[4] Checking for malicious processes...${NC}"
BAD_PROCS=$(ps aux | grep -iE "(xmrig|kinsing|kdevtmpfsi|bioset|crypto.*min|挖矿|minerd|masscan|zmap|\.hide|\.x25)" | grep -v grep)
if [ -n "$BAD_PROCS" ]; then
    threat "Known malware/miner processes found:"
    echo "$BAD_PROCS" | while IFS= read -r line; do echo "      $line"; done
else
    ok "No known malware processes"
fi
echo ""

# 5. Systemd services
echo -e "${YELLOW}[5] Checking for suspicious systemd services...${NC}"
KNOWN_SERVICES="dbus|systemd|NetworkManager|pipewire|wireplumber|bluetooth|polkit|fail2ban|clamav|cron|at|sshd|nftables|iptables|cups|avahi|accounts-daemon|udisks|power|upower|wpa|mod|login|journal|resolved|udevd|udev|hwdb|tmp|getty|user@|runtime|sddm|gdm|lightdm|lxdm|proton|warp|cloudflare|thermald|power-profiles|switcheroo|rtkit|colord|rtkit|cups-browsed|ModemManager|packagekit|firewalld|unattended|snapd|docker|containerd|libvirtd|lxc|frr|chronyd|ntpd|timesyncd|resolved|sleep|suspend|hibernate|hybrid|swap|logrotate|man-db|fstrim|logwatch|rsyslog|auditd|apparmor|selinux|aide|trippy|mullvad|privoxy|tor|iwd|wpa_supplicant|dhcpcd|systemd-timesyncd|systemd-networkd|systemd-resolved"
SUSPICIOUS_UNITS=$(systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | grep -viE "$KNOWN_SERVICES" | head -10)
if [ -n "$SUSPICIOUS_UNITS" ]; then
    warn "Review these running services:"
    echo "$SUSPICIOUS_UNITS" | while IFS= read -r line; do echo "      $line"; done
else
    ok "No unusual running services"
fi
echo ""

# 6. Listening ports
echo -e "${YELLOW}[6] Analyzing listening ports...${NC}"
SAFE_PORTS=":(22|80|443|53|631|3000|8080|8443|9090|67|68|5353|5432|3306|6379|27017|111|2049|8200|8888|5000|5355|1900|7946|2377|9100|9200|2375|2376|10250|10255|6443) "
UNUSUAL_PORTS=$(ss -tlnp 2>/dev/null | grep -vE "$SAFE_PORTS" | grep "LISTEN" | head -10)
if [ -n "$UNUSUAL_PORTS" ]; then
    warn "Ports listening (review these):"
    echo "$UNUSUAL_PORTS" | while IFS= read -r line; do echo "      $line"; done
else
    ok "No unusual listening ports"
fi
echo ""

# 7. Crontab backdoors
echo -e "${YELLOW}[7] Checking crontabs for malicious entries...${NC}"
CRON_SUSPICIOUS=""
for cronfile in /var/spool/cron/* /var/spool/cron/atjobs; do
    [ -f "$cronfile" ] || continue
    if grep -qiE "curl.*\|.*sh|wget.*\|.*sh|base64.*-d|nc -|/dev/tcp|python.*socket" "$cronfile" 2>/dev/null; then
        CRON_SUSPICIOUS="$CRON_SUSPICIOUS $cronfile"
    fi
done
if crontab -l 2>/dev/null | grep -qiE "curl.*\|.*sh|wget.*\|.*sh|base64.*-d|nc -|/dev/tcp|python.*socket"; then
    CRON_SUSPICIOUS="$CRON_SUSPICIOUS user-crontab"
fi
if [ -n "$CRON_SUSPICIOUS" ]; then
    threat "Suspicious crontab entries found: $CRON_SUSPICIOUS"
else
    ok "No malicious crontab entries"
fi
echo ""

# 8. World-writable files
echo -e "${YELLOW}[8] Checking for world-writable files in home...${NC}"
WORLD_WRITABLE=$(find ~ -maxdepth 3 -type f -perm -o+w ! -path "*/.cache/*" ! -path "*/tmp/*" 2>/dev/null | head -10)
if [ -z "$WORLD_WRITABLE" ]; then
    ok "No world-writable files"
else
    warn "World-writable files found:"
    echo "$WORLD_WRITABLE" | while IFS= read -r f; do echo "      $f"; done
fi
echo ""

# 9. Exposed private keys
echo -e "${YELLOW}[9] Checking for exposed private keys...${NC}"
EXPOSED=$(find ~ -maxdepth 4 -type f \( -name "id_rsa" -o -name "id_ed25519" -o -name "id_ecdsa" -o -name "*.pem" -o -name "*.key" \) ! -path "*/.ssh/*" ! -path "*/.cache/*" ! -path "*/node_modules/*" ! -path "*/.local/share/Trash/*" 2>/dev/null | head -10)
if [ -z "$EXPOSED" ]; then
    ok "No exposed private keys outside ~/.ssh"
else
    threat "Private keys found outside ~/.ssh:"
    echo "$EXPOSED" | while IFS= read -r f; do echo "      $f"; done
fi
echo ""

# 10. Firewall status
echo -e "${YELLOW}[10] Checking firewall...${NC}"
FW_OK=false
if command -v nft &>/dev/null; then
    NFT_RULES=$(nft list ruleset 2>/dev/null | wc -l)
    if [ "$NFT_RULES" -gt 5 ]; then
        ok "nftables active ($NFT_RULES rules)"
        FW_OK=true
    fi
fi
if [ "$FW_OK" = false ] && systemctl is-active --quiet nftables 2>/dev/null; then
    ok "nftables service running"
    FW_OK=true
fi
if [ "$FW_OK" = false ] && command -v iptables &>/dev/null; then
    IPT_RULES=$(iptables -L -n 2>/dev/null | wc -l)
    if [ "$IPT_RULES" -gt 8 ]; then
        ok "iptables active ($IPT_RULES rules)"
        FW_OK=true
    fi
fi
[ "$FW_OK" = false ] && warn "No active firewall detected"
echo ""

# 11. Package integrity
echo -e "${YELLOW}[11] Checking for failed package integrity...${NC}"
if command -v pacman &>/dev/null; then
    CORRUPT=$(pacman -Qk 2>&1 | grep -E "[0-9]+ files missing" | head -5)
    if [ -n "$CORRUPT" ]; then
        threat "Corrupted packages detected:"
        echo "$CORRUPT" | while IFS= read -r line; do echo "      $line"; done
    else
        ok "All installed packages intact"
    fi
fi
echo ""

# 12. Kernel modules
echo -e "${YELLOW}[12] Checking loaded kernel modules...${NC}"
KNOWN_MODULES="ext4|xfs|btrfs|vfat|fat|ntfs|fuse|usb|hid|input|sound|snd|drm|i915|nvidia|amdgpu|bluetooth|rfkill|tun|bridge|veth|overlay|loop|sr_mod|sd_mod|ahci|ata|nvme|nfs|cifs|ipv6|ip_tables|nf_|xt_|tcp|udp|bonding|8021q|virtio|kvm|kvm_amd|kvm_intel|cfg80211|mac80211|intel|amd|realtek|r8169|r8168|r8125|e1000|e1000e|igb|igc|i40e|bnxt|mlx|thunderbolt|pcspkr|joydev|evdev|pciehp|acpi|battery|button|processor|thermal|fan|joydev|ppp|slip|cdc|usbcore|usbhid|uhid|uinput|hid_generic|hid_apple|hid_logitech|nls|crc|crypto|aes|sha|md5|lzo|zstd|deflate|arc4|ccm|gcm|chacha|poly1305|nft_|nf_|xt_|ip6_|ip_|iptable|raw|conntrack|br_netfilter|stp|llc|8021q|dummy|dummy0|veth|tap|tun|bond|bonding|team|bridge|vrf|geneve|vxlan|wireguard|openvswitch|nbd|dm_|md_|raid|async|iscsi|target|fuse|cuse|bpf|btrfs|zram|zswap|crypto_|algif|af_alg"
SUSPICIOUS_MODS=$(lsmod 2>/dev/null | awk 'NR>1 && $3==0 {print $1}' | grep -viE "$KNOWN_MODULES" | head -5)
if [ -n "$SUSPICIOUS_MODS" ]; then
    warn "Unusual kernel modules loaded:"
    for mod in $SUSPICIOUS_MODS; do echo "      $mod"; done
else
    ok "No unusual kernel modules"
fi
echo ""

# 13. Keyloggers
echo -e "${YELLOW}[13] Checking for keylogger indicators...${NC}"
if [ -d /dev/input ]; then
    ok "/dev/input devices exist (normal)"
else
    ok "No keylogger indicators"
fi
echo ""

# 14. Failed login attempts
echo -e "${YELLOW}[14] Checking failed login attempts (24h)...${NC}"
FAILED=$(journalctl _COMM=sshd --since "24 hours ago" 2>/dev/null | grep -c "failed\|invalid" || true)
FAILED=$(echo "$FAILED" | tr -d '[:space:]')
FAILED=${FAILED:-0}
if [ "$FAILED" -gt 20 ] 2>/dev/null; then
    threat "Brute force detected: $FAILED failed SSH attempts in 24h"
elif [ "$FAILED" -gt 5 ] 2>/dev/null; then
    warn "$FAILED failed SSH attempts in 24h"
else
    ok "Failed SSH attempts: $FAILED (last 24h)"
fi
echo ""

# 15. Pending security updates
echo -e "${YELLOW}[15] Checking for security updates...${NC}"
if command -v checkupdates &>/dev/null; then
    UPDATES=$(checkupdates 2>/dev/null | wc -l)
    [ "${UPDATES:-0}" -gt 0 ] 2>/dev/null && warn "$UPDATES packages have updates available" || ok "System up to date"
else
    info "checkupdates not available (install pacman-contrib)"
fi
echo ""

# Summary
echo "=========================================="
if [ "$THREATS" -gt 0 ]; then
    echo -e "${RED}  AUDIT COMPLETE - $THREATS THREATS FOUND${NC}"
else
    echo -e "${GREEN}  AUDIT COMPLETE - NO THREATS DETECTED${NC}"
fi
echo "=========================================="
