--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

hl.window_rule({
    name  = "rofi-glass",
    match = { class = "rofi" },
    float = true,
})

hl.window_rule({
    name  = "mpv-float",
    match = { class = "mpv" },
    float = true,
    size  = "640 480",
})

hl.window_rule({
    name  = "loupe-float",
    match = { class = "org.gnome.Loupe" },
    float = true,
    size  = "640 480",
})

hl.window_rule({
    name  = "pavucontrol-float",
    match = { class = "org.pulseaudio.pavucontrol" },
    float = true,
})

hl.window_rule({
    name  = "brave-popup-float",
    match = {
        class         = "brave-browser",
        initial_title = "Untitled - Brave",
    },
    float = true,
    size  = "900 700",
})

hl.layer_rule({
    name        = "rofi-anim",
    match       = { namespace = "rofi" },
    animation   = "popin 87%",
    blur        = true,
    ignore_alpha = 0.05,
})

hl.layer_rule({
    name         = "swaync-glass",
    match        = { namespace = "swaync-notification-window" },
    blur         = false,
    ignore_alpha = 1,
})

hl.layer_rule({
    name        = "swaync-cc-glass",
    match       = { namespace = "swaync-control-center" },
    blur        = true,
    ignore_alpha = 0.05,
})





hl.window_rule({
    name  = "music-recognition-float",
    match = { class = "music_recognition.sh" },
    float = true,
    size  = "380 220",
    center = true,
})

hl.window_rule({
    name  = "scratchpad-clear",
    match = { workspace = "special:magic" },
    no_blur = true,
    opacity = "0.7 0.5",
})



