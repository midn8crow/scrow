#!/bin/bash
# Quick fix script for file permissions (no sudo needed)
# Run this first

echo "Fixing user file permissions..."

# SSH directory
chmod 700 ~/.ssh 2>/dev/null && echo "[OK] ~/.ssh -> 700" || echo "[SKIP] ~/.ssh not found"

# SSH keys
chmod 600 ~/.ssh/id_* 2>/dev/null && echo "[OK] Private keys -> 600" || echo "[SKIP] No private keys found"
chmod 600 ~/.ssh/*_key 2>/dev/null && echo "[OK] Key files -> 600" || echo "[SKIP] No key files found"
chmod 644 ~/.ssh/*.pub 2>/dev/null && echo "[OK] Public keys -> 644" || echo "[SKIP] No public keys found"

# History files
chmod 600 ~/.bash_history 2>/dev/null && echo "[OK] ~/.bash_history -> 600" || echo "[SKIP]"
chmod 600 ~/.zsh_history 2>/dev/null && echo "[OK] ~/.zsh_history -> 600" || echo "[SKIP]"

# Other sensitive files
chmod 600 ~/.gitconfig 2>/dev/null && echo "[OK] ~/.gitconfig -> 600" || echo "[SKIP]"
chmod 700 ~/.gnupg 2>/dev/null && echo "[OK] ~/.gnupg -> 700" || echo "[SKIP]"

echo ""
echo "Permission fixes complete."
