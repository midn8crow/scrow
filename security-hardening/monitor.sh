#!/bin/bash
# Security Monitor - Real-time threat detection

# Clear screen AND scrollback buffer
printf '\033[2J\033[H\033[3J'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

show_monitor() {
    printf '\033[2J\033[H\033[3J'
    echo -e "${YELLOW}=========================================="
    echo "    SECURITY MONITOR - $(date)"
    echo -e "==========================================${NC}"
    echo ""

    echo -e "${CYAN}[Failed Login Attempts (1h)]${NC}"
    FAILED=$(journalctl _COMM=sshd --since "1 hour ago" 2>/dev/null | grep -ci "failed\|invalid" 2>/dev/null || echo 0)
    if [ "$FAILED" -gt 5 ]; then
        echo -e "  ${RED}ALERT: $FAILED failed attempts!${NC}"
        journalctl _COMM=sshd --since "1 hour ago" 2>/dev/null | grep -i "failed\|invalid" | tail -3
    elif [ "$FAILED" -gt 0 ]; then
        echo -e "  ${YELLOW}$FAILED failed attempts${NC}"
    else
        echo -e "  ${GREEN}None${NC}"
    fi
    echo ""

    echo -e "${CYAN}[Active SSH Sessions]${NC}"
    SSH_SESSIONS=$(who 2>/dev/null | grep pts | wc -l)
    if [ "$SSH_SESSIONS" -gt 2 ]; then
        echo -e "  ${RED}ALERT: $SSH_SESSIONS active sessions${NC}"
    fi
    who 2>/dev/null | grep pts | head -5 || echo -e "  ${GREEN}None${NC}"
    echo ""

    echo -e "${CYAN}[Suspicious Processes]${NC}"
    BAD=$(ps aux 2>/dev/null | grep -iE "(xmrig|kinsing|kdevtmpfsi|cryptominer|masscan|zmap|nc -[el]|ncat)" | grep -v grep | head -5)
    if [ -n "$BAD" ]; then
        echo -e "  ${RED}THREAT DETECTED:${NC}"
        echo "$BAD" | while read line; do echo "      $line"; done
    else
        echo -e "  ${GREEN}None detected${NC}"
    fi
    echo ""

    echo -e "${CYAN}[Top CPU Processes]${NC}"
    ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5
    echo ""

    echo -e "${CYAN}[Memory Usage]${NC}"
    free -h 2>/dev/null | awk 'NR==1{print} NR==2{print}'
    echo ""

    echo -e "${CYAN}[Network Connections]${NC}"
    # Flag foreign connections on unusual ports
    UNUSUAL_NET=$(ss -tn 2>/dev/null | grep -vE ":(22|80|443|53|631|3000|8080) " | grep "ESTAB" | head -5)
    if [ -n "$UNUSUAL_NET" ]; then
        echo -e "  ${YELLOW}Connections on unusual ports:${NC}"
        echo "$UNUSUAL_NET" | while read line; do echo "      $line"; done
    else
        ss -tn 2>/dev/null | head -8 || echo -e "  ${GREEN}None${NC}"
    fi
    echo ""

    echo -e "${CYAN}[Listening Ports]${NC}"
    ss -tlnp 2>/dev/null | grep -vE ":(22|80|443|53|631) " | head -5
    LISTEN_COUNT=$(ss -tlnp 2>/dev/null | grep -c "LISTEN")
    echo -e "  Total: $LISTEN_COUNT ports listening"
    echo ""

    echo -e "${CYAN}[Disk Usage]${NC}"
    DISK_PCT=$(df -h / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "${DISK_PCT:-0}" -gt 90 ]; then
        echo -e "  ${RED}CRITICAL: ${DISK_PCT}% used!${NC}"
    elif [ "${DISK_PCT:-0}" -gt 75 ]; then
        echo -e "  ${YELLOW}WARNING: ${DISK_PCT}% used${NC}"
    else
        df -h / 2>/dev/null | tail -1 | awk '{print "  Root: " $5 " used (" $3 "/" $2 ")"}'
    fi
    echo ""

    echo -e "${CYAN}[Package Integrity]${NC}"
    if command -v pacman &>/dev/null; then
        CORRUPT=$(pacman -Qk 2>&1 | grep -c "files missing" 2>/dev/null || echo 0)
        if [ "$CORRUPT" -gt 0 ]; then
            echo -e "  ${RED}ALERT: $CORRUPT corrupted packages!${NC}"
        else
            echo -e "  ${GREEN}All packages intact${NC}"
        fi
    fi
    echo ""

    echo -e "${GREEN}Press 'q' to back, any other key to refresh...${NC}"
}

while true; do
    show_monitor
    read -rsn1 key
    if [[ "$key" == "q" || "$key" == "Q" ]]; then
        printf '\033[2J\033[H'
        break
    fi
done
