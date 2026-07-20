#!/bin/bash
# Security Monitor - Real-time monitoring script
# Run without sudo for user-level monitoring

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear
echo "=========================================="
echo "    SECURITY MONITOR (Ctrl+C to exit)"
echo "=========================================="
echo ""

while true; do
    clear
    echo "=========================================="
    echo "    SECURITY MONITOR - $(date)"
    echo "=========================================="
    echo ""
    
    # Failed SSH attempts
    echo -e "${YELLOW}[Failed Login Attempts]${NC}"
    journalctl -u sshd --since "1 hour ago" 2>/dev/null | grep -i "failed\|invalid" | tail -5 || echo "  No failed attempts"
    echo ""
    
    # Current SSH sessions
    echo -e "${YELLOW}[Active SSH Sessions]${NC}"
    who 2>/dev/null | grep pts | head -5 || echo "  No active sessions"
    echo ""
    
    # High CPU processes
    echo -e "${YELLOW}[Top CPU Processes]${NC}"
    ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5
    echo ""
    
    # Memory usage
    echo -e "${YELLOW}[Memory Usage]${NC}"
    free -h 2>/dev/null | head -2
    echo ""
    
    # Network connections
    echo -e "${YELLOW}[Recent Connections]${NC}"
    ss -tn 2>/dev/null | head -10 || echo "  No connections"
    echo ""
    
    # Disk usage warning
    echo -e "${YELLOW}[Disk Usage]${NC}"
    df -h / 2>/dev/null | tail -1 | awk '{print "Root partition: " $5 " used (" $3 "/" $2 ")"}'
    
    echo ""
    echo "Refreshing in 10 seconds..."
    sleep 10
done
