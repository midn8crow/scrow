#!/bin/bash
# =============================================================================
# update-dots.sh - Private Push Menu (ONLY FOR ME)
# =============================================================================
# Push local changes to GitHub
# =============================================================================

DOTFILES_DIR="$HOME/dotfiles"

CHOICE=$(printf "Push All\nPush Configs Only\nPush Scripts Only\nView Status" | rofi -dmenu -p "Push Dots" -theme-str 'configuration { show-icons: false; }')

[ -z "$CHOICE" ] && exit 0

case "$CHOICE" in
    "Push All")
        cd "$DOTFILES_DIR" || exit 1
        
        cp -r "$HOME/.config/hypr" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp -r "$HOME/.config/waybar" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp -r "$HOME/.config/kitty" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp -r "$HOME/.config/rofi" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp -r "$HOME/.config/mako" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp "$HOME/.config/starship.toml" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp -r "$HOME/.local/bin/"* "$DOTFILES_DIR/.local/bin/" 2>/dev/null
        cp -r "$HOME/user_scripts/"* "$DOTFILES_DIR/user_scripts/" 2>/dev/null
        cp "$HOME/.zshrc" "$DOTFILES_DIR/" 2>/dev/null
        
        CHANGES=$(git status --short | wc -l)
        
        if [[ "$CHANGES" -eq 0 ]]; then
            notify-send "Push" "Nothing to push"
        else
            git add .
            git commit -m "Updated dotfiles $(date +%Y-%m-%d_%H:%M)"
            git push
            notify-send "Done!" "Pushed $CHANGES changes to GitHub"
        fi
        ;;
    "Push Configs Only")
        cd "$DOTFILES_DIR" || exit 1
        
        cp -r "$HOME/.config/hypr" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp -r "$HOME/.config/waybar" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp -r "$HOME/.config/kitty" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp -r "$HOME/.config/rofi" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp -r "$HOME/.config/mako" "$DOTFILES_DIR/.config/" 2>/dev/null
        cp "$HOME/.config/starship.toml" "$DOTFILES_DIR/.config/" 2>/dev/null
        
        CHANGES=$(git status --short | wc -l)
        
        if [[ "$CHANGES" -eq 0 ]]; then
            notify-send "Push" "Nothing to push"
        else
            git add .
            git commit -m "Updated configs $(date +%Y-%m-%d_%H:%M)"
            git push
            notify-send "Done!" "Pushed configs to GitHub"
        fi
        ;;
    "Push Scripts Only")
        cd "$DOTFILES_DIR" || exit 1
        
        cp -r "$HOME/.local/bin/"* "$DOTFILES_DIR/.local/bin/" 2>/dev/null
        cp -r "$HOME/user_scripts/"* "$DOTFILES_DIR/user_scripts/" 2>/dev/null
        
        CHANGES=$(git status --short | wc -l)
        
        if [[ "$CHANGES" -eq 0 ]]; then
            notify-send "Push" "Nothing to push"
        else
            git add .
            git commit -m "Updated scripts $(date +%Y-%m-%d_%H:%M)"
            git push
            notify-send "Done!" "Pushed scripts to GitHub"
        fi
        ;;
    "View Status")
        cd "$DOTFILES_DIR" || exit 1
        
        # Count changes between home and dotfiles folder
        TOTAL=0
        
        # Check config changes
        for dir in hypr waybar kitty rofi mako; do
            DIFF=$(diff -rq "$HOME/.config/$dir" "$DOTFILES_DIR/.config/$dir" 2>/dev/null | wc -l)
            TOTAL=$((TOTAL + DIFF))
        done
        
        # Check starship
        if [ -f "$HOME/.config/starship.toml" ] && [ -f "$DOTFILES_DIR/.config/starship.toml" ]; then
            DIFF=$(diff -q "$HOME/.config/starship.toml" "$DOTFILES_DIR/.config/starship.toml" 2>/dev/null | wc -l)
            TOTAL=$((TOTAL + DIFF))
        fi
        
        # Check scripts
        DIFF=$(diff -rq "$HOME/.local/bin" "$DOTFILES_DIR/.local/bin" 2>/dev/null | wc -l)
        TOTAL=$((TOTAL + DIFF))
        
        # Check zshrc
        if [ -f "$HOME/.zshrc" ] && [ -f "$DOTFILES_DIR/.zshrc" ]; then
            DIFF=$(diff -q "$HOME/.zshrc" "$DOTFILES_DIR/.zshrc" 2>/dev/null | wc -l)
            TOTAL=$((TOTAL + DIFF))
        fi
        
        if [[ "$TOTAL" -eq 0 ]]; then
            notify-send "Dotfiles Status" "All changes pushed to GitHub"
        else
            notify-send "Dotfiles Status" "$TOTAL changes not pushed to GitHub"
        fi
        ;;
esac
