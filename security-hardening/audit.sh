#!/bin/bash
# Security Audit Script - Run without sudo for user-level checks
# For full audit, run with sudo

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "       SECURITY AUDIT REPORT"
echo "=========================================="
echo ""

# 1. Check file permissions
echo -e "${YELLOW}[1] Checking sensitive file permissions...${NC}"
echo ""

# SSH directory
if [ -d ~/.ssh ]; then
    SSH_PERMS=$(stat -c %a ~/.ssh 2>/dev/null)
    if [ "$SSH_PERMS" = "700" ]; then
        echo -e "  ${GREEN}[OK]${NC} ~/.ssh directory: $SSH_PERMS"
    else
        echo -e "  ${RED}[FIX]${NC} ~/.ssh directory: $SSH_PERMS (should be 700)"
    fi
    
    for keyfile in ~/.ssh/*; do
        if [ -f "$keyfile" ]; then
            KEY_PERMS=$(stat -c %a "$keyfile" 2>/dev/null)
            if [[ "$keyfile" == *".pub" ]]; then
                if [ "$KEY_PERMS" = "644" ]; then
                    echo -e "  ${GREEN}[OK]${NC} $keyfile: $KEY_PERMS"
                else
                    echo -e "  ${YELLOW}[WARN]${NC} $keyfile: $KEY_PERMS (recommended: 644)"
                fi
            else
                if [ "$KEY_PERMS" = "600" ]; then
                    echo -e "  ${GREEN}[OK]${NC} $keyfile: $KEY_PERMS"
                else
                    echo -e "  ${RED}[FIX]${NC} $keyfile: $KEY_PERMS (should be 600)"
                fi
            fi
        fi
    done
else
    echo -e "  ${GREEN}[OK]${NC} No ~/.ssh directory found"
fi

echo ""

# 2. Check bash history permissions
echo -e "${YELLOW}[2] Checking history file permissions...${NC}"
for histfile in ~/.bash_history ~/.zsh_history; do
    if [ -f "$histfile" ]; then
        HIST_PERMS=$(stat -c %a "$histfile" 2>/dev/null)
        if [ "$HIST_PERMS" = "600" ] || [ "$HIST_PERMS" = "640" ]; then
            echo -e "  ${GREEN}[OK]${NC} $histfile: $HIST_PERMS"
        else
            echo -e "  ${RED}[FIX]${NC} $histfile: $HIST_PERMS (should be 600)"
        fi
    fi
done

echo ""

# 3. Check for world-writable files in home
echo -e "${YELLOW}[3] Checking for world-writable files in home...${NC}"
WORLD_WRITABLE=$(find ~ -maxdepth 2 -type f -perm -o+w 2>/dev/null | head -10)
if [ -z "$WORLD_WRITABLE" ]; then
    echo -e "  ${GREEN}[OK]${NC} No world-writable files found"
else
    echo -e "  ${RED}[WARN]${NC} World-writable files found:"
    echo "$WORLD_WRITABLE" | while read f; do echo "    $f"; done
fi

echo ""

# 4. Check for SUID/SGID files
echo -e "${YELLOW}[4] Checking for SUID/SGID files in home...${NC}"
SUID_FILES=$(find ~ -maxdepth 3 -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | head -10)
if [ -z "$SUID_FILES" ]; then
    echo -e "  ${GREEN}[OK]${NC} No SUID/SGID files in home"
else
    echo -e "  ${YELLOW}[INFO]${NC} SUID/SGID files found:"
    echo "$SUID_FILES" | while read f; do echo "    $f"; done
fi

echo ""

# 5. Check running processes
echo -e "${YELLOW}[5] Checking for suspicious processes...${NC}"
SUSPICIOUS=$(ps aux | grep -E "(nc |ncat |netcat |socat |cryptominer|xmrig|kinsing)" | grep -v grep)
if [ -z "$SUSPICIOUS" ]; then
    echo -e "  ${GREEN}[OK]${NC} No suspicious processes detected"
else
    echo -e "  ${RED}[ALERT]${NC} Suspicious processes found:"
    echo "$SUSPICIOUS"
fi

echo ""

# 6. Check listening ports (user-level)
echo -e "${YELLOW}[6] Checking listening ports...${NC}"
if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | head -20
elif command -v netstat &>/dev/null; then
    netstat -tlnp 2>/dev/null | head -20
else
    echo -e "  ${YELLOW}[SKIP]${NC} Neither ss nor netstat available"
fi

echo ""

# 7. Check for pending security updates
echo -e "${YELLOW}[7] Checking for security updates...${NC}"
if command -v checkupdates &>/dev/null; then
    UPDATES=$(checkupdates 2>/dev/null | wc -l)
    if [ "$UPDATES" -gt 0 ]; then
        echo -e "  ${YELLOW}[WARN]${NC} $UPDATES packages have updates available"
        checkupdates 2>/dev/null | head -10
    else
        echo -e "  ${GREEN}[OK]${NC} System is up to date"
    fi
else
    echo -e "  ${YELLOW}[SKIP]${NC} checkupdates not available (install pacman-contrib)"
fi

echo ""

# 8. Check firewall status
echo -e "${YELLOW}[8] Checking firewall status...${NC}"
if command -v nft &>/dev/null; then
    RULES=$(nft list ruleset 2>/dev/null | wc -l)
    if [ "$RULES" -gt 5 ]; then
        echo -e "  ${GREEN}[OK]${NC} nftables has rules loaded ($RULES lines)"
    else
        echo -e "  ${RED}[WARN]${NC} nftables appears to have no rules"
    fi
fi

echo ""

# 9. Check SSH config
echo -e "${YELLOW}[9] Checking SSH server configuration...${NC}"
if [ -f /etc/ssh/sshd_config ]; then
    PERMIT_ROOT=$(grep -i "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    PASS_AUTH=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    
    if [ -z "$PERMIT_ROOT" ] || [ "$PERMIT_ROOT" = "prohibit-password" ] || [ "$PERMIT_ROOT" = "no" ]; then
        echo -e "  ${GREEN}[OK]${NC} Root login: ${PERMIT_ROOT:-default(prohibit-password)}"
    else
        echo -e "  ${RED}[FIX]${NC} Root login: $PERMIT_ROOT (should be 'no')"
    fi
    
    if [ "$PASS_AUTH" = "no" ]; then
        echo -e "  ${GREEN}[OK]${NC} Password auth: disabled"
    else
        echo -e "  ${YELLOW}[WARN]${NC} Password auth: ${PASS_AUTH:-yes} (should be 'no')"
    fi
fi

echo ""

# 10. Check for exposed keys
echo -e "${YELLOW}[10] Checking for exposed private keys...${NC}"
EXPOSED_KEYS=$(find ~ -maxdepth 3 -type f \( -name "*.pem" -o -name "*.key" -o -name "id_rsa" -o -name "id_ed25519" -o -name "id_ecdsa" \) ! -path "*/.ssh/*" 2>/dev/null | head -10)
if [ -z "$EXPOSED_KEYS" ]; then
    echo -e "  ${GREEN}[OK]${NC} No exposed private keys found outside ~/.ssh"
else
    echo -e "  ${RED}[WARN]${NC} Private keys found outside ~/.ssh:"
    echo "$EXPOSED_KEYS" | while read f; do echo "    $f"; done
fi

echo ""
echo "=========================================="
echo "       AUDIT COMPLETE"
echo "=========================================="
echo ""
echo "For full system audit, run with sudo:"
echo "  sudo ./apply-security.sh"
