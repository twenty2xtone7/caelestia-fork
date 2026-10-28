local vars = require("variables")

-- True when hy3 is usable: either already loaded, or marked enabled in
-- hyprpm's state (covers boot, where plugins load after this config).
-- Everything hy3-specific keys off this so the config is clean with or
-- without the plugin.
local function hy3_available()
    local ok, mod = pcall(function() return hl.plugin.hy3 end)
    if ok and mod ~= nil then return true end

    local user = os.getenv("USER") or os.getenv("LOGNAME")
    if not user or user == "" then
        user = (os.getenv("HOME") or ""):match("([^/]+)$")
    end
    if user and user ~= "" then
        local f = io.open("/var/cache/hyprpm/" .. user .. "/hy3/state.toml", "r")
        if f then
            local content = f:read("*a")
            f:close()
            if content and content:find("enabled%s*=%s*true") then return true end
        end
    end
    return false
end

local has_hy3 = hy3_available()

hl.config({
    general = {
        layout          = has_hy3 and "hy3" or "dwindle",

        allow_tearing   = false, -- Allows `immediate` window rule to work

        gaps_workspaces = vars.workspaceGaps,
        gaps_in         = vars.windowGapsIn,
        gaps_out        = vars.windowGapsOut,
        border_size     = vars.windowBorderSize,

        col             = {
            active_border   = vars.activeWindowBorderColour,
            inactive_border = vars.inactiveWindowBorderColour,
        },
    },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
        smart_resizing = true,
    },

    scrolling = {
        fullscreen_on_one_column = false,
        focus_fit_method         = 1,
        column_width             = 0.5,
        follow_focus             = true,
        follow_min_visible       = 0.0,
        explicit_column_widths   = "0.35, 0.5, 0.65, 1.0",
    },
})

-- hy3 plugin options: only set when the plugin is available, so a
-- disabled/missing hy3 can't produce unknown-option config errors.
if hl.plugin.hy3 then
    hl.config({
        plugin = {
            hy3 = {
                node_collapse_policy = 2,
                group_inset = 0,
                tabs = {
                    height = 22,
                    padding = 6,
                    from_top = false,
                    radius = 6,
                    border_width = 2,
                    render_text = true,
                },
                autotile = {
                    enable = false,
                },
            },
        },
    })
  end
