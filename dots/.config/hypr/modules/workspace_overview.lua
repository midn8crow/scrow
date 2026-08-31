---------------------------
---- WORKSPACE OVERVIEW ----
---------------------------

-- Only configure ScrollOverview if the plugin is actually installed
if hl.plugin and hl.plugin.scrolloverview then
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
else
    if hl.notification and hl.notification.create then
        hl.notification.create({
            text = "ScrollOverview plugin not installed — run: hyprpm add https://github.com/yayuuu/hyprland-scroll-overview.git",
            timeout = 8000,
        })
    end
end
