----------------------
---- PERMISSIONS ----
----------------------

-- Allow hyprpm to load plugins without an interactive permission popup.
-- (Hyprland's Lua permission API; guarded so older Hyprland versions still
-- load this module without error.)
if hl.permission then
    hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")
end