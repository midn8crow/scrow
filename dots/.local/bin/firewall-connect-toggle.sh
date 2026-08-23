#!/bin/bash
# Toggle KDE Connect / LocalSend ports (1716, 53317, 5353) in the nftables
# input chain. Adds/removes ONLY these rules - no other firewall rules are
# touched or reloaded.

STATE_FILE="$HOME/.config/scrow/settings/connectfw"
mkdir -p "$(dirname "$STATE_FILE")"

RULES=(
    "tcp dport 1716 accept"
    "udp dport 1716 accept"
    "tcp dport 53317 accept"
    "udp dport 53317 accept"
    "udp dport 5353 accept"
)

# Prompt for the sudo password first so the nft commands below run non-stop.
if ! sudo -v; then
    notify-send -u critical "Connect Firewall" "sudo failed - ports left locked"
    exit 1
fi

# Decide from the live rules, not the state file, so a stale state file
# (e.g. after a reboot that reloaded the locked base) can't invert the toggle.
if sudo nft list chain inet filter input 2>/dev/null | grep -q 'dport 1716 accept'; then
    # nft can only delete by handle, so resolve the handles of the accept
    # rules first. The awk pattern matches only our 5 rules, never the
    # set-based drop rules (e.g. the 5353 in the dangerous list).
    handles=$(sudo nft -a list chain inet filter input 2>/dev/null |
        awk '/(tcp|udp) dport (1716|53317|5353) accept/ {print $NF}')
    for h in $handles; do
        sudo nft delete rule inet filter input handle "$h" 2>/dev/null
    done
    echo "closed" > "$STATE_FILE"
    notify-send "Connect Firewall" "Locked - KDE Connect/LocalSend ports closed"
else
    for r in "${RULES[@]}"; do
        sudo nft insert rule inet filter input $r 2>/dev/null
    done
    echo "open" > "$STATE_FILE"
    notify-send "Connect Firewall" "Unlocked - KDE Connect/LocalSend ports open"
fi
