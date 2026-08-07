---------------------
---- MY PROGRAMS ----
---------------------

-- set programs that you use
local terminal    = "kitty"
local fileManager = "bash -c 'desktop=$(xdg-mime query default inode/directory 2>/dev/null); f=$(find /usr/share/applications ~/.local/share/applications -name \"$desktop\" 2>/dev/null | head -1); exec=\"$(grep ^Exec= \"$f\" 2>/dev/null | head -1 | cut -d= -f2-)\"; term=$(grep ^Terminal= \"$f\" 2>/dev/null | cut -d= -f2-); cmd=\"${exec%% %*}\"; [ \"$term\" = \"true\" ] && cmd=\"kitty $cmd\"; eval \"$cmd\"'"
local browser     = "bash -c 'desktop=$(xdg-settings get default-web-browser 2>/dev/null); f=$(find /usr/share/applications ~/.local/share/applications -name \"$desktop\" 2>/dev/null | head -1); exec=\"$(grep ^Exec= \"$f\" 2>/dev/null | head -1 | cut -d= -f2-)\"; exec ${exec%% %*}'"
local menu        = "rofi -show drun -drun-prompt Software"
local wayclick    = "$HOME/.local/bin/wayclick.sh"





---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + ALT + X", hl.dsp.exec_cmd("$HOME/.local/bin/force-kill.sh"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + D", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen())
-- Custom maximize toggle that saves/restores tiling state
-- See: https://github.com/hyprwm/Hyprland/discussions/14380
local fs_saved = {}
local dwindle_fs_saved = {}
local ws_layouts = {}

local function is_dwindle()
    local ws = hl.get_active_workspace()
    return ws_layouts[tostring(ws.id)] == "dwindle"
end

local function get_window_dims(w)
    local mon = w.monitor
    if not mon then return nil end
    local mon_x = (mon.position and (mon.position.x or mon.position[1])) or mon.x or 0
    local mon_w = mon.width or mon.w or (mon.size and (mon.size.x or mon.size[1]))
    local win_x = (w.at and (w.at.x or w.at[1])) or (w.position and (w.position.x or w.position[1])) or w.x
    local win_w = w.width or w.w or (w.size and (w.size.x or w.size[1]))
    if not (mon_w and win_x and win_w) or mon_w == 0 then return nil end
    return {
        width = win_w / mon_w,
        anchor = (win_x - mon_x) / mon_w,
    }
end

local function snap_width(width)
    local snaps = { 0.333, 0.5, 0.667 }
    local best, best_dist = 0.5, math.huge
    for _, v in ipairs(snaps) do
        local d = math.abs(width - v)
        if d < best_dist then best, best_dist = v, d end
    end
    return best
end

hl.bind(mainMod .. " + SHIFT + A", function()
    local w = hl.get_active_window()
    if w == nil then return end
    local addr = w.address

    if is_dwindle() then
        if addr and dwindle_fs_saved[addr] then
            dwindle_fs_saved[addr] = nil
            hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
            hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
        else
            dwindle_fs_saved[addr] = true
            hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
        end
    else
        if addr and fs_saved[addr] then
            local s = fs_saved[addr]
            fs_saved[addr] = nil
            hl.dispatch(hl.dsp.layout("colresize " .. tostring(s.width)))
            if s.anchor > 0.02 then
                local last = -1
                for _ = 1, 12 do
                    local cw = hl.get_active_window()
                    local d = cw and get_window_dims(cw)
                    local cur = d and d.anchor
                    if not cur or cur >= s.anchor - 0.02 then break end
                    if math.abs(cur - last) < 0.004 then break end
                    last = cur
                    hl.dispatch(hl.dsp.layout("move -col"))
                end
            end
            hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
        else
            local d = get_window_dims(w)
            if addr then
                fs_saved[addr] = {
                    width = d and snap_width(d.width) or 0.5,
                    anchor = d and d.anchor or 0,
                }
            end
            hl.dispatch(hl.dsp.layout("colresize 1.0"))
        end
    end
end, { description = "Maximize" })

hl.on("window.close", function(w)
    if w and w.address then
        fs_saved[w.address] = nil
        dwindle_fs_saved[w.address] = nil
    end
end)

-- Scrolling layout fullscreen workaround
-- Entering fullscreen re-fits the tape flush-left; on exit the viewport stays
-- put, so a window fullscreened from a right-hand column ends up flush-left.
-- Remember its on-screen anchor before fullscreen and scroll the tape back.
local fs_anchor = {}
local win_anchor = {}

local function monitor_width(w)
    local mon = w and w.monitor
    if not mon then return nil end
    return mon.width or mon.w or (mon.size and (mon.size.x or mon.size[1]))
end

hl.on("window.active", function(w)
    if not w or not w.address or is_dwindle() or w.floating then return end
    if w.fullscreen and w.fullscreen ~= 0 then return end
    local d = get_window_dims(w)
    if d then win_anchor[w.address] = d.anchor end
end)

hl.on("window.fullscreen", function(w)
    if not w or not w.address or is_dwindle() or w.floating then return end
    local fs = w.fullscreen or 0
    if fs ~= 0 then
        if win_anchor[w.address] ~= nil then
            fs_anchor[w.address] = win_anchor[w.address]
        end
    else
        local target = fs_anchor[w.address]
        fs_anchor[w.address] = nil
        if target then
            local d = get_window_dims(w)
            local mon_w = monitor_width(w)
            if d and mon_w then
                local delta = (target - d.anchor) * mon_w
                if math.abs(delta) > 5 then
                    local sign = delta > 0 and "+" or "-"
                    hl.dispatch(hl.dsp.layout("move " .. sign .. tostring(math.abs(math.floor(delta)))))
                end
            end
        end
    end
end)

hl.on("window.close", function(w)
    if w and w.address then
        fs_anchor[w.address] = nil
        win_anchor[w.address] = nil
    end
end)
hl.bind("ALT + space", hl.dsp.exec_cmd(menu))
hl.bind("CTRL + space", hl.dsp.exec_cmd("$HOME/.local/bin/wallpaper-menu.sh"))
hl.bind("ALT + SHIFT + space", hl.dsp.exec_cmd("$HOME/.local/bin/powermenu.sh"))
hl.bind("ALT + R", hl.dsp.exec_cmd("$HOME/.local/bin/gpu-recorder.sh"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only
hl.bind(mainMod .. " + ALT + W", hl.dsp.exec_cmd("bash -c 'pkill waybar && sleep 0.3 || $HOME/.config/waybar/launch.sh'"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("$HOME/.local/bin/wallpaper-switch.sh"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("$HOME/.local/bin/wallpaper-switch.sh prev"))
hl.bind("ALT + W", hl.dsp.exec_cmd("$HOME/.config/waybar/switch-waybar.sh next"))
hl.bind("ALT + SHIFT + W", hl.dsp.exec_cmd("$HOME/.config/waybar/switch-waybar.sh prev"))
hl.bind("SUPER + ALT + RIGHT", hl.dsp.exec_cmd("$HOME/.local/bin/vol-notify.sh up"), { repeating = true })
hl.bind("SUPER + ALT + LEFT", hl.dsp.exec_cmd("$HOME/.local/bin/vol-notify.sh down"), { repeating = true })
hl.bind("ALT + UP",    hl.dsp.window.cycle_next({ next = true, floating = true }))
hl.bind("ALT + DOWN",  hl.dsp.window.cycle_next({ next = true, tiled = true }))
hl.bind("ALT + 0", hl.dsp.exec_cmd("$HOME/.config/waybar/launch.sh"))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("$HOME/.local/bin/rofi-mako.sh"))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("hyprctl reload"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind("ALT + V", hl.dsp.exec_cmd("$HOME/.local/bin/rofi-clipboard.sh"))
hl.bind("CTRL + SUPER + space", hl.dsp.exec_cmd("$HOME/.local/bin/emoji-launch.sh"))
hl.bind("ALT + C", hl.dsp.exec_cmd("$HOME/.local/bin/rofi-calculator.sh"))
hl.bind("CTRL + SHIFT + space", hl.dsp.exec_cmd("kitty --class scrow-tui -o remember_window_size=no -o initial_window_width=820 -o initial_window_height=36c -e $HOME/.local/bin/scrow-menu-tui --keybinds"))
local blur_off = {}
hl.bind(mainMod .. " + period", function()
    local w = hl.get_active_window()
    if not w then return end
    local a = w.address
    if blur_off[a] then
        hl.dispatch(hl.dsp.window.set_prop({ prop = "opaque", value = "0", window = "activewindow" }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "no_blur", value = "0", window = "activewindow" }))
        blur_off[a] = nil
    else
        hl.dispatch(hl.dsp.window.set_prop({ prop = "opaque", value = "1", window = "activewindow" }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "no_blur", value = "1", window = "activewindow" }))
        blur_off[a] = true
    end
end, { description = "Toggle Blur & Opacity", locked = true })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("kitty --class scrow-tui -o remember_window_size=no -o initial_window_width=820 -o initial_window_height=36c -e $HOME/.local/bin/scrow-menu-tui"))
hl.bind(mainMod .. " + SHIFT + U", hl.dsp.exec_cmd("$HOME/.local/bin/update-dots.sh"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("$HOME/.local/bin/pick-color-region.sh"))
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("$HOME/.local/bin/ocr-toggle.sh"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("$HOME/.local/bin/screenshot-region.sh"))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("$HOME/.local/bin/secure-tunnel.sh"))
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("$HOME/.local/bin/video-compressor.sh"))
hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd("$HOME/.local/bin/screenshot-full.sh"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("fcitx5-remote -t"))

-- Google Lens (Circle to Search)
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("$HOME/user_scripts/google_image_search/google_image_search.sh"))

-- Control Center (WiFi & Bluetooth)
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("$HOME/.local/bin/control-center.sh"))

-- Music Recognition (Shazam)
hl.bind(mainMod .. " + ALT + M", hl.dsp.exec_cmd("kitty --class music_recognition.sh $HOME/user_scripts/music/music_recognition.sh"))

-- Notification actions (Mako)
hl.bind(mainMod .. " + ALT + D", hl.dsp.exec_cmd("makoctl dismiss -a"), { locked = true, description = "Dismiss All Notifications" })
hl.bind(mainMod .. " + ALT + F", hl.dsp.exec_cmd("makoctl menu -- rofi -dmenu -p 'Action: '"), { description = "Toggle Do Not Disturb" })




-- Layout toggle: scrolling <-> dwindle (current workspace only)
hl.bind(mainMod .. " + SHIFT + L", function()
    local ws = hl.get_active_workspace()
    local id = tostring(ws.id)
    if ws_layouts[id] == nil then
        ws_layouts[id] = "scrolling"
    end
    if ws_layouts[id] == "scrolling" then
        ws_layouts[id] = "dwindle"
    else
        ws_layouts[id] = "scrolling"
    end
    hl.workspace_rule({ workspace = id, layout = ws_layouts[id] })
end)

-- Move focus with mainMod + arrow keys; move the window if it's floating
local float_move_step = 20

local function move_float_or_focus(dx, dy, dir)
    return function()
        local w = hl.get_active_window()
        if w and w.floating then
            hl.dispatch(hl.dsp.window.move({ x = dx, y = dy, relative = true }))
        else
            hl.dispatch(hl.dsp.focus({ direction = dir }))
        end
    end
end

hl.bind(mainMod .. " + left",  move_float_or_focus(-float_move_step, 0, "left"),   { repeating = true })
hl.bind(mainMod .. " + right", move_float_or_focus(float_move_step, 0, "right"),  { repeating = true })
hl.bind(mainMod .. " + up",    move_float_or_focus(0, -float_move_step, "up"),    { repeating = true })
hl.bind(mainMod .. " + down",  move_float_or_focus(0, float_move_step, "down"),   { repeating = true })

-- Swap window with mainMod + SHIFT + arrow keys
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.swap({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.swap({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.swap({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.swap({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + Z", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + Z", function()
    local w = hl.get_active_window()
    if not w then return end
    local ws = (w.workspace and w.workspace.name) or ""
    if ws == "special:magic" then
        local mon = hl.get_active_monitor()
        local target = mon and mon.activeWorkspace and mon.activeWorkspace.id or 1
        hl.dispatch(hl.dsp.window.move({ workspace = target }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "no_blur", value = "unset", window = "activewindow" }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_override", value = "unset", window = "activewindow" }))
    else
        hl.dispatch(hl.dsp.window.move({ workspace = "special:magic" }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "no_blur", value = "1", window = "activewindow" }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_override", value = "1", window = "activewindow" }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = "0.7", window = "activewindow" }))
    end
end)

-- Switch workspaces with mainMod + SHIFT + scroll
hl.bind(mainMod .. " + SHIFT + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
-- Scroll columns in scrolling layout with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.layout("focus l"))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.layout("focus r"))


-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Keyboard-driven continuous resize (colresize in scrolling, splitratio in dwindle)
local function resize_layout(delta)
    return function()
        if is_dwindle() then
            hl.dispatch(hl.dsp.layout("splitratio " .. (delta > 0 and "+" or "") .. delta))
        else
            hl.dispatch(hl.dsp.layout("colresize " .. (delta > 0 and "+" or "") .. delta))
        end
    end
end
hl.bind(mainMod .. " + CTRL + left",  resize_layout(-0.02), { repeating = true })
hl.bind(mainMod .. " + CTRL + right", resize_layout(0.02),  { repeating = true })
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.resize({ x = 0,  y = 5,  relative = true }), { repeating = true })
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.resize({ x = 0,  y = -5, relative = true }), { repeating = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Mechanical keypress sounds (WayClick) toggle
hl.bind("CTRL + SHIFT + X", hl.dsp.exec_cmd(wayclick))
