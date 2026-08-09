#!/usr/bin/env bash
# Shared definitions for the rofi app launcher tabs (Apps / All Apps / System Apps).
# Single source of truth for which apps count as "system apps".

declare -A SYSTEM_APPS=(
    ["Volume Control"]="pavucontrol"
    ["NetworkManager Applet"]="nm-applet"
    ["Network Connections"]="nm-connection-editor"
    ["Bluetooth Manager"]="blueman-manager"
    ["Print Settings"]="system-config-printer"
    ["Fcitx 5"]="fcitx5"
    ["Fcitx 5 Configuration"]="fcitx5-configtool"
    ["OpenBangla Keyboard"]="openbangla-gui"
    ["Qt6 Settings"]="qt6ct"
    ["Keyboard Layout Viewer"]="kbd-layout-viewer5"
    ["User Unit Manager"]="uuctl"
    ["About System"]="xfce4-about"
    ["Bluetooth Adapters"]="blueman-adapters"
    ["Fcitx 5 Migration Wizard"]="fcitx5-migrator"
    ["Avahi Zeroconf Browser"]="avahi-discover"
    ["Avahi SSH Server Browser"]="bssh"
    ["Avahi VNC Server Browser"]="bvnc"
    ["Hardware Locality lstopo"]="lstopo"
    ["Manage Printing"]="xdg-open http://localhost:631/"
    ["Qt V4L2 test Utility"]="qv4l2"
    ["Qt V4L2 video capture utility"]="qvidcap"
    ["xgps"]="xgps"
    ["xgpsspeed"]="xgpsspeed"
    ["Cloudflare One Client"]="warp-cli --accept-tos registration token"
    ["Proton VPN"]="protonvpn-app"
    ["KDE Connect"]="kdeconnect-app"
    ["KDE Connect Indicator"]="kdeconnect-indicator"
    ["KDE Connect SMS"]="kdeconnect-sms"
    ["SongRec"]="songrec gui"
    ["Rofi"]="rofi -show"
    ["Rofi Theme Selector"]="rofi-theme-selector"
    ["Bulk Rename"]="thunar --bulk-rename"
    ["Thunar Preferences"]="thunar-settings"
    ["Image Viewer"]="loupe"
    ["File Roller"]="file-roller"
    ["Tor Browser Launcher Settings"]="torbrowser-launcher --settings"
)

declare -A SYSTEM_APP_ICONS=(
    ["Volume Control"]="org.pulseaudio.pavucontrol"
    ["NetworkManager Applet"]="nm-device-wireless"
    ["Network Connections"]="preferences-system-network"
    ["Bluetooth Manager"]="blueman"
    ["Print Settings"]="printer"
    ["Fcitx 5"]="fcitx"
    ["Fcitx 5 Configuration"]="fcitx"
    ["OpenBangla Keyboard"]="openbangla-keyboard"
    ["Qt6 Settings"]="preferences-desktop-theme"
    ["Keyboard Layout Viewer"]="input-keyboard"
    ["User Unit Manager"]="applications-system"
    ["About System"]="org.xfce.about"
    ["Bluetooth Adapters"]="blueman-device"
    ["Fcitx 5 Migration Wizard"]="fcitx"
    ["Avahi Zeroconf Browser"]="network-wired"
    ["Avahi SSH Server Browser"]="network-wired"
    ["Avahi VNC Server Browser"]="network-wired"
    ["Hardware Locality lstopo"]="hwloc"
    ["Manage Printing"]="cups"
    ["Qt V4L2 test Utility"]="qv4l2"
    ["Qt V4L2 video capture utility"]="qvidcap"
    ["xgps"]="gpsd-logo"
    ["xgpsspeed"]="gpsd-logo"
    ["Cloudflare One Client"]="zero-trust-orange"
    ["Proton VPN"]="proton-vpn-logo"
    ["KDE Connect"]="kdeconnect"
    ["KDE Connect Indicator"]="kdeconnect"
    ["KDE Connect SMS"]="kdeconnect"
    ["SongRec"]="re.fossplant.songrec"
    ["Rofi"]="rofi"
    ["Rofi Theme Selector"]="rofi"
    ["Bulk Rename"]="org.xfce.thunar"
    ["Thunar Preferences"]="org.xfce.thunar"
    ["Image Viewer"]="org.gnome.Loupe"
    ["File Roller"]="org.gnome.FileRoller"
    ["Tor Browser Launcher Settings"]="org.torproject.torbrowser-launcher"
)

# .desktop filenames backing each system app, used to exclude them from
# the normal "Apps" tab regardless of the localized Name.
declare -A SYSTEM_APP_FILES=(
    ["org.pulseaudio.pavucontrol.desktop"]=1
    ["nm-applet.desktop"]=1
    ["nm-connection-editor.desktop"]=1
    ["blueman-manager.desktop"]=1
    ["system-config-printer.desktop"]=1
    ["org.fcitx.Fcitx5.desktop"]=1
    ["fcitx5-configtool.desktop"]=1
    ["openbangla-keyboard.desktop"]=1
    ["qt6ct.desktop"]=1
    ["kbd-layout-viewer5.desktop"]=1
    ["uuctl.desktop"]=1
    ["xfce4-about.desktop"]=1
    ["blueman-adapters.desktop"]=1
    ["org.fcitx.fcitx5-migrator.desktop"]=1
    ["avahi-discover.desktop"]=1
    ["bssh.desktop"]=1
    ["bvnc.desktop"]=1
    ["lstopo.desktop"]=1
    ["cups.desktop"]=1
    ["qv4l2.desktop"]=1
    ["qvidcap.desktop"]=1
    ["xgps.desktop"]=1
    ["xgpsspeed.desktop"]=1
    ["com.cloudflare.warp.desktop"]=1
    ["proton.vpn.app.gtk.desktop"]=1
    ["org.kde.kdeconnect.app.desktop"]=1
    ["org.kde.kdeconnect.nonplasma.desktop"]=1
    ["org.kde.kdeconnect.sms.desktop"]=1
    ["re.fossplant.songrec.desktop"]=1
    ["rofi.desktop"]=1
    ["rofi-theme-selector.desktop"]=1
    ["thunar-bulk-rename.desktop"]=1
    ["thunar-settings.desktop"]=1
    ["org.gnome.Loupe.desktop"]=1
    ["org.gnome.FileRoller.desktop"]=1
    ["org.torproject.torbrowser-launcher.settings.desktop"]=1
)

is_system_app() {
    [ -n "${SYSTEM_APPS[$1]+x}" ]
}

is_system_app_file() {
    [ -n "${SYSTEM_APP_FILES[$1]+x}" ]
}
