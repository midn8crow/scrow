#!/bin/bash
# AUR Package Security Checker (paru version)
# Checks PKGBUILD for suspicious patterns before installing

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Cleanup on exit
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null
}
trap cleanup EXIT

# Validate input
if [ -z "$1" ]; then
    echo "Usage: $0 <package-name>"
    echo "Example: $0 neofetch"
    exit 1
fi

# Sanitize package name (only allow ASCII alphanumeric, hyphens, underscores, dots)
PACKAGE=$(echo "$1" | LC_ALL=C grep -oE '^[a-zA-Z0-9._-]+$' || true)
if [ -z "$PACKAGE" ]; then
    echo -e "${RED}[ERROR]${NC} Invalid package name: '$1'"
    echo "Package names can only contain: a-z A-Z 0-9 . _ -"
    exit 1
fi

echo "=========================================="
echo "  AUR Security Check: $PACKAGE"
echo "=========================================="
echo ""

# Step 1: Get package info from AUR
echo -e "${YELLOW}[1/4] Fetching package info...${NC}"
echo ""

# Search AUR for the package
AUR_INFO=$(curl -s "https://aur.archlinux.org/rpc/v5/info/$PACKAGE" 2>/dev/null)

if [ -z "$AUR_INFO" ]; then
    echo -e "${RED}[ERROR]${NC} Failed to fetch package info from AUR"
    exit 1
fi

if echo "$AUR_INFO" | grep -q '"resultcount":0'; then
    echo -e "${RED}[ERROR]${NC} Package '$PACKAGE' not found in AUR"
    exit 1
fi

# Extract info
NAME=$(echo "$AUR_INFO" | grep -o '"Name":"[^"]*"' | head -1 | cut -d'"' -f4)
VERSION=$(echo "$AUR_INFO" | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4)
DESCRIPTION=$(echo "$AUR_INFO" | grep -o '"Description":"[^"]*"' | head -1 | cut -d'"' -f4)
URL=$(echo "$AUR_INFO" | grep -o '"URL":"[^"]*"' | head -1 | cut -d'"' -f4)
MAINTAINER=$(echo "$AUR_INFO" | grep -o '"Maintainer":"[^"]*"' | head -1 | cut -d'"' -f4)
VOTES=$(echo "$AUR_INFO" | grep -o '"NumVotes":[0-9]*' | head -1 | cut -d':' -f2)
POPULARITY=$(echo "$AUR_INFO" | grep -o '"Popularity":[0-9.]*' | head -1 | cut -d':' -f2)

echo -e "  ${CYAN}Name:$NC $NAME"
echo -e "  ${CYAN}Version:$NC $VERSION"
echo -e "  ${CYAN}Description:$NC $DESCRIPTION"
echo -e "  ${CYAN}URL:$NC $URL"
echo -e "  ${CYAN}Maintainer:$NC $MAINTAINER"
echo -e "  ${CYAN}Votes:$NC $VOTES"
echo -e "  ${CYAN}Popularity:$NC $POPULARITY"

# Check votes
if [ "$VOTES" -lt 10 ] 2>/dev/null; then
    echo -e "  ${RED}[WARNING]${NC} Low votes ($VOTES) - package may be risky"
fi

echo ""

# Step 2: Clone and inspect PKGBUILD
echo -e "${YELLOW}[2/4] Downloading PKGBUILD...${NC}"
echo ""

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

# Clone from AUR (only PKGBUILD, not full repo)
git clone --depth 1 --single-branch "https://aur.archlinux.org/$PACKAGE.git" 2>/dev/null || {
    echo -e "${RED}[ERROR]${NC} Could not download PKGBUILD"
    exit 1
}

PKGBUILD_PATH="$TEMP_DIR/$PACKAGE/PKGBUILD"

if [ ! -f "$PKGBUILD_PATH" ]; then
    echo -e "${RED}[ERROR]${NC} PKGBUILD not found in repository"
    exit 1
fi

echo -e "  ${GREEN}[OK]${NC} PKGBUILD downloaded"
echo ""

# Step 3: Scan for suspicious patterns
echo -e "${YELLOW}[3/4] Scanning for suspicious patterns...${NC}"
echo ""

SUSPICIOUS=0

# Dangerous commands (comprehensive patterns)
declare -A PATTERNS=(
    # System destruction
    ["rm -rf /"]="System wipe (deletes entire system)"
    ["rm -rf /\*"]="System wipe (deletes everything)"
    
    # Remote code execution
    ["curl.*\|.*bash"]="Remote code execution via bash"
    ["wget.*\|.*bash"]="Remote code execution via bash"
    ["curl.*\|.*sh"]="Remote code execution via sh"
    ["wget.*\|.*sh"]="Remote code execution via sh"
    ["curl.*\|.*zsh"]="Remote code execution via zsh"
    ["wget.*\|.*zsh"]="Remote code execution via zsh"
    
    # Code execution
    ["eval\("]="Dynamic code execution"
    ["exec\("]="Process execution"
    ["nohup .* &"]="Background process execution"
    
    # Encoded/hidden payloads
    ["base64 -d.*\|.*bash"]="Encoded payload execution"
    ["base64 -d.*\|.*sh"]="Encoded payload execution"
    ["echo.*\|.*base64.*\|.*bash"]="Encoded payload execution"
    
    # Permission escalation
    ["chmod 777 /"]="Dangerous permissions on root"
    ["chmod \+s"]="SUID escalation"
    ["chmod 4755"]="SUID escalation"
    ["chown root"]="Permission escalation"
    
    # Data theft
    ["/etc/shadow"]="Password hash access"
    ["/etc/passwd"]="User data access"
    ["\.ssh/id"]="SSH key theft"
    ["\.ssh/authorized"]="SSH key theft"
    ["\.ssh/config"]="SSH config access"
    ["\.gnupg"]="PGP key theft"
    
    # Surveillance
    ["keylog"]="Keylogging"
    ["keylogger"]="Keylogging"
    ["screen.*-d.*-r"]="Screen capture"
    
    # Network backdoors
    ["nc -l -p"]="Netcat listener"
    ["nc -e"]="Netcat with execute"
    ["ncat -l"]="Backdoor listener"
    ["ncat.*-e"]="Backdoor with execute"
    ["/dev/tcp"]="Network connection"
    ["python.*socket"]="Python network socket"
    
    # Disk destruction
    ["mkfs\."]="Filesystem formatting"
    ["dd if=.*of=/dev/"]="Disk overwrite"
    ["dd if=.*of=/dev/sd"]="Disk overwrite"
    
    # Scheduled tasks
    ["crontab -e"]="Scheduled task creation"
    ["crontab -r"]="Cron job deletion"
    
    # Python/Perl execution
    ["python -c.*import os"]="Python system call"
    ["python -c.*subprocess"]="Python subprocess execution"
    ["perl -e.*system"]="Perl system call"
    ["perl -e.*exec"]="Perl exec call"
    
    # Process manipulation
    ["killall"]="Mass process termination"
    ["pkill -9"]="Force kill all"
    ["kill -9.*\$PPID"]="Kill parent process"
)

for pattern in "${!PATTERNS[@]}"; do
    if grep -qiE "$pattern" "$PKGBUILD_PATH" 2>/dev/null; then
        echo -e "  ${RED}[SUSPICIOUS]${NC} Found '$pattern' - ${PATTERNS[$pattern]}"
        SUSPICIOUS=$((SUSPICIOUS + 1))
    fi
done

# Check for network access
if grep -qiE "curl|wget|git clone|http|https|ftp" "$PKGBUILD_PATH" 2>/dev/null; then
    echo -e "  ${YELLOW}[INFO]${NC} Package downloads from internet"
fi

# Check for systemd services
if grep -qiE "systemctl|\.service" "$PKGBUILD_PATH" 2>/dev/null; then
    echo -e "  ${YELLOW}[INFO]${NC} Package installs systemd services"
fi

# Check for cron jobs
if grep -qiE "crontab|cron\.d|/etc/cron" "$PKGBUILD_PATH" 2>/dev/null; then
    echo -e "  ${YELLOW}[INFO]${NC} Package installs cron jobs"
fi

# Check for kernel modules
if grep -qiE "insmod|modprobe|\.ko" "$PKGBUILD_PATH" 2>/dev/null; then
    echo -e "  ${YELLOW}[INFO]${NC} Package loads kernel modules"
fi

echo ""

# Step 4: Show PKGBUILD content
echo -e "${YELLOW}[4/4] PKGBUILD Content...${NC}"
echo ""
echo -e "${CYAN}----------------------------------------${NC}"
cat "$PKGBUILD_PATH"
echo -e "${CYAN}----------------------------------------${NC}"
echo ""

# Summary
echo "=========================================="
if [ $SUSPICIOUS -gt 0 ]; then
    echo -e "${RED}  WARNING: $SUSPICIOUS suspicious patterns found!${NC}"
    echo "  Do NOT install without reviewing PKGBUILD."
else
    echo -e "${GREEN}  No obvious threats detected.${NC}"
    echo "  But always review PKGBUILDs before installing."
fi
echo "=========================================="
