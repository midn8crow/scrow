#!/bin/bash
# Post-apply steps that run after matugen has written all component colors.
# Browser theme reloads (via Browser Toolbox) and the non-color qt6ct side effect.

# Reload Firefox styles via Browser Toolbox
if pgrep -x firefox >/dev/null 2>&1; then
  hyprctl eval 'hl.dsp.event("focuswindow", "class:^(firefox)$")' 2>/dev/null
  sleep 0.5
  if hyprctl clients -j 2>/dev/null | python3 -c "import sys,json; sys.exit(0 if any(c.get('class','').lower()=='firefox' and c.get('focus',{}).get('address','')!='' for c in json.load(sys.stdin)) else 1)" 2>/dev/null; then
    wtype -M ctrl -M shift -M alt -k i -m ctrl -m shift -m alt 2>/dev/null
    sleep 1.5
    wtype -M ctrl -M shift -k r -m ctrl -m shift 2>/dev/null
    sleep 1
    wtype -M ctrl -M shift -M alt -k i -m ctrl -m shift -m alt 2>/dev/null
  fi
fi

# Reload Zen styles via Browser Toolbox
if pgrep -x zen >/dev/null 2>&1; then
  hyprctl eval 'hl.dsp.event("focuswindow", "class:^(zen)$")' 2>/dev/null
  sleep 0.5
  if hyprctl clients -j 2>/dev/null | python3 -c "import sys,json; sys.exit(0 if any(c.get('class','').lower()=='zen' and c.get('focus',{}).get('address','')!='' for c in json.load(sys.stdin)) else 1)" 2>/dev/null; then
    wtype -M ctrl -M shift -M alt -k i -m ctrl -m shift -m alt 2>/dev/null
    sleep 1.5
    wtype -M ctrl -M shift -k r -m ctrl -m shift 2>/dev/null
    sleep 1
    wtype -M ctrl -M shift -M alt -k i -m ctrl -m shift -m alt 2>/dev/null
  fi
fi

# Reload Brave theme
if pgrep -x brave >/dev/null 2>&1; then
  hyprctl eval 'hl.dsp.event("focuswindow", "class:^(brave-browser)$")' 2>/dev/null
  sleep 0.5
  if hyprctl clients -j 2>/dev/null | python3 -c "import sys,json; sys.exit(0 if any(c.get('class','').lower()=='brave-browser' and c.get('focus',{}).get('address','')!='' for c in json.load(sys.stdin)) else 1)" 2>/dev/null; then
    wtype -M ctrl -k l -m ctrl 2>/dev/null
    sleep 0.2
    wtype "brave://extensions" 2>/dev/null
    wtype -k Return 2>/dev/null
    sleep 1.5
    wtype -M ctrl -k r -m ctrl 2>/dev/null
    sleep 0.3
    wtype -M ctrl -k w -m ctrl 2>/dev/null
  fi
fi

# Qt6 color scheme (Fusion dark)
cat > "$HOME/.config/qt6ct/qt6ct.conf" << QEOF
[Appearance]
color_scheme_path=
icon_theme=$(grep gtk-icon-theme-name "$HOME/.config/gtk-3.0/settings.ini" | cut -d= -f2)
style=Fusion
color_scheme_type=2
QEOF
