
-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")

-- Load saved cursor theme or default to Adwaita
local cursor_file = io.open(os.getenv("HOME") .. "/.config/hypr/.cursor-theme", "r")
local cursor_theme = "Adwaita"
if cursor_file then
    local saved = cursor_file:read("*l")
    cursor_file:close()
    if saved and saved ~= "" then
        cursor_theme = saved
    end
end
hl.env("XCURSOR_THEME", cursor_theme)
hl.env("HYPRCURSOR_SIZE", "24")

hl.env("GTK_THEME", "adw-gtk3-dark")
hl.env("ADWAITA_PREFER_DARK_THEME", "1")
hl.env("ADWAITA_COLOR_SCHEME", "prefer-dark")
hl.env("GNOME_KEYRING_CONTROL", "/run/user/" .. (io.popen("id -u"):read("*a"):match("%d+") or "1000") .. "/keyring")

--Toolkit Backend--
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

-- xdg --
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

--Qt--
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

--Fcitx5--
hl.env("XMODIFIERS", "@im=fcitx")

--AMD Performance--
hl.env("AMD_VULKAN_ICD", "RADV")
hl.env("RADV_PERFTEST", "gpl")
hl.env("mesa_glthread", "true")
hl.env("vblank_mode", "0")

--NVIDIA (from Hyprland Wiki)--
hl.env("NVD_BACKEND", "direct")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVIDIA_NO_OVERLAY", "1")
hl.env("__NV_PRIME_RENDER_OFFLOAD", "1")
hl.env("__GL_GSYNC_ALLOWED", "1")
hl.env("__GL_VRR_ALLOWED", "1")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
