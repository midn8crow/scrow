---------------------------
---- WORKSPACE OVERVIEW ----
---------------------------

-- Hyprexpo workspace overview plugin config + keybind
hl.config({
    plugin = {
        hyprexpo = {
            columns = 3,
            gaps_in = 5,
            gaps_out = 0,
            bg_col = "rgb(1E1E2E)",
            workspace_method = "center current",
            gesture_distance = 300,
            cancel_key = "escape",
            show_cursor = 1,
        },
    },
})

hl.bind("SUPER + O", function()
    hl.plugin.hyprexpo.expo("toggle")
end)
