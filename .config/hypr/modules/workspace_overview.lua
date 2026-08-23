---------------------------
---- WORKSPACE OVERVIEW ----
---------------------------

-- ScrollOverview plugin config + keybind
-- Wrapped in pcall so a missing plugin never breaks autostart or other modules.
local ok = pcall(function()
    hl.config({
        plugin = {
            scrolloverview = {
                gesture_distance = 300,
                scale = 0.5,
                workspace_gap = 100,
                layout = "vertical",
                wallpaper = 0,
                blur = false,
                shadow = {
                    enabled = false,
                    range = 50,
                    render_power = 3,
                    color = 0xee1a1a1a,
                },
            },
        },
    })

    hl.bind("SUPER + O", function()
        hl.plugin.scrolloverview.overview("toggle")
    end)
end)

if not ok then
    hl.log("workspace_overview: ScrollOverview plugin not installed — skipping (run: hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git)")
end
