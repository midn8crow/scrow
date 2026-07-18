
-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 4,
        gaps_out = 10,

        border_size = 1,

        col = {
            active_border   = { colors = { "rgba(33ccffee)" } },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 7,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 0.78,
        inactive_opacity = 0.60,

        shadow = {
            enabled      = true,
            range        = 25,
            render_power = 4,
            color        = 0xdd0a0a0a,
        },

        blur = {
            enabled   = true,
            size      = 6,
            passes    = 3,
            vibrancy  = 0.1696,
            ignore_opacity = true,
            noise     = 0.0117,
            contrast  = 0.8916,
            brightness = 0.8172,
        },
    },

    animations = {
        enabled = true,
    },
})

-- scrow curves
hl.curve("overshot",  { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.1} } })
hl.curve("fluid",     { type = "bezier", points = { {0.25, 1}, {0, 1} } })
hl.curve("snap",      { type = "bezier", points = { {0.5, 0.9}, {0.1, 1.05} } })
hl.curve("menu_decel",{ type = "bezier", points = { {0.1, 1}, {0, 1} } })
hl.curve("liner",     { type = "bezier", points = { {1, 1}, {1, 1} } })

hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 6,  bezier = "overshot",   style = "popin 80%",  bezier = "overshot",   style = "popin 80%",  bezier = "overshot",   style = "popin 80%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 4,  bezier = "snap",       style = "popin 80%",  bezier = "snap",       style = "popin 80%",  bezier = "snap",       style = "popin 80%" })
hl.animation({ leaf = "windowsMove",   enabled = true,  speed = 6,  bezier = "overshot",   style = "slide",  bezier = "overshot",   style = "slide",  bezier = "overshot",   style = "slide" })
hl.animation({ leaf = "border",        enabled = true,  speed = 2,  bezier = "liner" })
hl.animation({ leaf = "borderangle",   enabled = true,  speed = 40, bezier = "liner",      style = "once" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 4,  bezier = "fluid",  bezier = "fluid",  bezier = "fluid" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 5,  bezier = "overshot",   style = "popin 70%",  bezier = "overshot",   style = "popin 70%",  bezier = "overshot",   style = "popin 70%" })
hl.animation({ leaf = "layersOut",     enabled = false })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 5,  bezier = "menu_decel" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 4,  bezier = "menu_decel" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 7,  bezier = "overshot",   style = "slidevert",  bezier = "overshot",   style = "slidevert",  bezier = "overshot",   style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 7, bezier = "overshot", style = "slidevert", bezier = "overshot", style = "slidevert", bezier = "overshot", style = "slidevert" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
hl.workspace_rule({ workspace = "special:magic", gaps_in = 12, gaps_out = 24 })
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
        explicit_column_widths = "0.5, 1",
    },
})

----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = 0,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = true, -- If true disables the random hyprland logo / anime girl background. :(
    },
})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})

