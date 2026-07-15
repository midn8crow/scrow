
-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
  hl.on("hyprland.start", function () 
      hl.exec_cmd("$HOME/.config/waybar/launch.sh")
      hl.exec_cmd("swaync")
      hl.exec_cmd("awww-daemon")
      hl.exec_cmd("swww-daemon")
      hl.exec_cmd("$HOME/.local/bin/wallpaper-switch.sh")
      hl.exec_cmd("setsid bash -c 'wl-paste --watch cliphist store' </dev/null >/dev/null 2>&1 &")
      hl.exec_cmd("fcitx5")
 end)

