local vars = require("variables")
local fn   = require("utils.functions")

-- hy3 is optional: resolve it lazily (at keypress time, inside a bind
-- action) so this config loads and works whether or not the plugin is
-- enabled, regardless of plugin/config load ordering.
local function hy3_mod()
    local ok, mod = pcall(function() return hl.plugin.hy3 end)
    if ok and type(mod) == "table" then return mod end
    return nil
end

-- Build a bind action that uses hy3 when enabled, else a stock fallback.
-- `make_disp` receives the hy3 module and returns a dispatcher;
-- `fallback` is a dispatcher (or function) used when hy3 is missing.
-- With no fallback the bind is inert while hy3 is disabled.
local function with_hy3(make_disp, fallback)
    return function()
        local mod = hy3_mod()
        if mod then
            local ok, disp = pcall(make_disp, mod)
            if ok and disp ~= nil then return hl.dispatch(disp) end
        end
        if fallback ~= nil then
            if type(fallback) == "function" then return fallback() end
            return hl.dispatch(fallback)
        end
    end
end


-- Flags
local locked           = { locked = true }
local mouse            = { mouse = true }
local release          = { release = true }
local repeating        = { repeating = true }
local locked_repeating = { locked = true, repeating = true }

local function normalise_keybind(key)
    return key:gsub("%s+", ""):lower()
end

local function valid_keybind(key)
    return type(key) == "string" and key:match("%S") ~= nil
end

local function repeating_unless_mouse(key)
    return not normalise_keybind(key):find("mouse", 1, true) and repeating or nil
end

local function flatten_keybinds(keybinds, keys)
    keys = keys or {}

    if type(keybinds) == "table" then
        for _, keybind in pairs(keybinds) do
            flatten_keybinds(keybind, keys)
        end
    elseif valid_keybind(keybinds) then
        keys[#keys + 1] = keybinds
    end

    return keys
end

local function create_bind(keybinds, action, flags)
    local get_flags = type(flags) == "function" and flags or function()
        return flags
    end

    for _, key in ipairs(flatten_keybinds(keybinds)) do
        hl.bind(key, action, get_flags(key))
    end
end

local function extend_keybind(base, suffix)
    return valid_keybind(base) and base .. " + " .. suffix or nil
end

-- Launcher
local launcher_default = normalise_keybind("SUPER + SUPER_L")
create_bind(
    vars.kbLauncher,
    hl.dsp.global("caelestia:launcher"),
    function(key)
        return normalise_keybind(key) == launcher_default and release or nil
    end
)

-- Misc
create_bind(vars.kbSession, hl.dsp.global("caelestia:session"))
create_bind(vars.kbShowSidebar, hl.dsp.global("caelestia:sidebar"))
create_bind(vars.kbClearNotifs, hl.dsp.global("caelestia:clearNotifs"), locked)
create_bind(vars.kbShowPanels, hl.dsp.global("caelestia:showall"))
create_bind(vars.kbLock, hl.dsp.global("caelestia:lock"))

-- Restore lock
create_bind(vars.kbRestoreLock, function()
    hl.dispatch(hl.dsp.exec_cmd("caelestia shell -d"))
    hl.dispatch(hl.dsp.global("caelestia:lock"))
end)

-- Kill/restart
create_bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c caelestia kill"), release)
create_bind(
    "CTRL + SUPER + ALT + R",
    hl.dsp.exec_cmd("qs -c caelestia kill; sleep .1; caelestia shell -d"),
    release
)

for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    create_bind(extend_keybind(vars.kbGoToWs, key), fn.wsaction("focus", "", i))
    create_bind(extend_keybind(vars.kbMoveWinToWs, key), fn.wsaction("move", "", i))
    create_bind(extend_keybind(vars.kbGoToWsGroup, key), fn.wsaction("focus", "group", i))
    create_bind(extend_keybind(vars.kbMoveWinToWsGroup, key), fn.wsaction("move", "group", i))
end

-- Go to workspace -1/+1
create_bind(vars.kbPrevWs, hl.dsp.focus({ workspace = "-1" }), repeating_unless_mouse)
create_bind(vars.kbNextWs, hl.dsp.focus({ workspace = "+1" }), repeating_unless_mouse)

-- Go to workspace group -1/+1
create_bind(vars.kbPrevWsGroup, hl.dsp.focus({ workspace = "-10" }), repeating_unless_mouse)
create_bind(vars.kbNextWsGroup, hl.dsp.focus({ workspace = "+10" }), repeating_unless_mouse)

-- Move window to workspace -1/+1 (hy3 node-aware when enabled, stock otherwise)
create_bind(
    vars.kbMoveWinToWsNext,
    with_hy3(
        function(m) return m.move_to_workspace("+1") end,
        hl.dsp.window.move({ workspace = "+1" })
    ),
    repeating_unless_mouse
)
create_bind(
    vars.kbMoveWinToWsPrev,
    with_hy3(
        function(m) return m.move_to_workspace("-1") end,
        hl.dsp.window.move({ workspace = "-1" })
    ),
    repeating_unless_mouse
)

-- Move window to/from special workspace (hy3 node-aware when enabled)
create_bind(
    vars.kbMoveWinToWsSpecial,
    with_hy3(
        function(m) return m.move_to_workspace("special:special") end,
        hl.dsp.window.move({ workspace = "special:special" })
    )
)
create_bind(
    vars.kbMoveWinFromWsSpecial,
    with_hy3(
        function(m) return m.move_to_workspace("e+0") end,
        hl.dsp.window.move({ workspace = "e+0" })
    )
)

-- Window groups
create_bind(vars.kbWindowCycleNext, hl.dsp.window.cycle_next(), repeating)
create_bind(vars.kbWindowCyclePrev, hl.dsp.window.cycle_next({ next = false }), repeating)
create_bind(vars.kbWindowGroupCycleNext, hl.dsp.group.next(), repeating)
create_bind(vars.kbWindowGroupCyclePrev, hl.dsp.group.prev(), repeating)
create_bind(vars.kbToggleGroup, hl.dsp.group.toggle())
create_bind(vars.kbUngroup, hl.dsp.window.move({ out_of_group = true }))
create_bind(vars.kbGroupLockActive, hl.dsp.group.lock_active())

-- Window focus/move: hy3 when enabled, stock dispatchers otherwise.
-- (hy3 docs: replace movefocus -> hy3:movefocus, movewindow -> hy3:movewindow)
local hy3_short = { left = "l", right = "r", up = "u", down = "d" }
for _, dir in ipairs({ "left", "right", "up", "down" }) do
    local short = hy3_short[dir]
    create_bind(
        "SUPER + " .. dir,
        with_hy3(
            function(m) return m.move_focus(short) end,
            hl.dsp.focus({ direction = dir })
        )
    )
    create_bind(
        "SUPER + SHIFT + " .. dir,
        with_hy3(
            function(m) return m.move_window(short) end,
            hl.dsp.window.move({ direction = dir })
        )
    )
end



-- hy3 groups / tabs (inert while hy3 is disabled)
create_bind(vars.kbHy3MakeGroupH, with_hy3(function(m) return m.make_group("h") end))
create_bind(vars.kbHy3MakeGroupV, with_hy3(function(m) return m.make_group("v") end))
create_bind(vars.kbHy3MakeGroupTab, with_hy3(function(m) return m.make_group("tab") end))
create_bind(vars.kbHy3ChangeToTab, with_hy3(function(m) return m.change_group("toggletab") end))
create_bind(vars.kbHy3ChangeOpposite, with_hy3(function(m) return m.change_group("opposite") end))
create_bind(vars.kbHy3KillActive, with_hy3(function(m) return m.kill_active() end))
create_bind(
    vars.kbHy3FocusTabNext,
    with_hy3(function(m) return m.focus_tab({ direction = "r", wrap = true }) end),
    repeating
)
create_bind(
    vars.kbHy3FocusTabPrev,
    with_hy3(function(m) return m.focus_tab({ direction = "l", wrap = true }) end),
    repeating
)
create_bind(vars.kbHy3Expand, with_hy3(function(m) return m.expand("expand") end))
create_bind(vars.kbHy3Shrink, with_hy3(function(m) return m.expand("shrink") end))
create_bind("SUPER + SHIFT + CTRL + O", with_hy3(function(m) return m.expand("base") end))

create_bind(vars.kbWindowDecreaseWidth, fn.resize_active_window(-10, 0), repeating)
create_bind(vars.kbWindowIncreaseWidth, fn.resize_active_window(10, 0), repeating)
create_bind(vars.kbWindowDecreaseHeight, fn.resize_active_window(0, -10), repeating)
create_bind(vars.kbWindowIncreaseHeight, fn.resize_active_window(0, 10), repeating)

create_bind({ vars.kbMoveWindow, "SUPER + mouse:272" }, hl.dsp.window.drag(), mouse)
create_bind({ vars.kbResizeWindow, "SUPER + mouse:273" }, hl.dsp.window.resize(), mouse)
create_bind(vars.kbCenterWindow, hl.dsp.window.center())
create_bind(vars.kbNormalizeWindow, function()
    hl.dispatch(hl.dsp.window.resize(fn.resize_by_screen(55, 70)))
    hl.dispatch(hl.dsp.window.center())
end)
create_bind(vars.kbWindowPip, function()
    local a = hl.get_active_window()
    if a then
        local pip = fn.move_actions(a) or {}
        if not a.floating then table.insert(pip, 1, hl.dsp.window.float()) end
        table.insert(pip, hl.dsp.window.pin({ action = "on", window = "address:" .. a.address }))

        for _, x in ipairs(pip) do
            hl.dispatch(x)
        end
    end
end)
create_bind(vars.kbPinWindow, hl.dsp.window.pin())
create_bind(vars.kbWindowFullscreen, hl.dsp.window.fullscreen({ mode = "fullscreen" }))
create_bind(vars.kbWindowBorderedFullscreen, hl.dsp.window.fullscreen({ mode = "maximized" }))
create_bind(vars.kbToggleWindowFloating, hl.dsp.window.float())
create_bind(vars.kbCloseWindow, hl.dsp.window.close())

-- Special workspace toggles
create_bind(vars.kbSpecialWs, fn.toggle("specialws"))
create_bind(vars.kbSystemMonitorWs, fn.toggle("sysmon"))
create_bind(vars.kbMusicWs, fn.toggle("music"))
create_bind(vars.kbCommunicationWs, fn.toggle("communication"))
create_bind(vars.kbTodoWs, fn.toggle("todo"))

-- Apps
create_bind(vars.kbTerminal, hl.dsp.exec_cmd(vars.terminal))
create_bind(vars.kbBrowser, hl.dsp.exec_cmd(vars.browser))
create_bind(vars.kbEditor, hl.dsp.exec_cmd(vars.editor))
create_bind(vars.kbFileExplorer, hl.dsp.exec_cmd(vars.fileExplorer))
create_bind(vars.kbAudioSettings, hl.dsp.exec_cmd(vars.audioSettings))

-- Utilities
create_bind(vars.kbScreenshot, hl.dsp.exec_cmd("caelestia screenshot"), locked)
create_bind(vars.kbScreenshotFreeze, hl.dsp.global("caelestia:screenshotFreeze"))
create_bind(vars.kbScreenshotRegion, hl.dsp.global("caelestia:screenshot"))
create_bind(vars.kbRecord, hl.dsp.exec_cmd("caelestia record"))
create_bind(vars.kbRecordSound, hl.dsp.exec_cmd("caelestia record -s"))
create_bind(vars.kbRecordRegion, hl.dsp.exec_cmd("caelestia record -r"))
create_bind(vars.kbColorPicker, hl.dsp.exec_cmd("hyprpicker -a"))

-- Brightness
create_bind("XF86MonBrightnessUp", hl.dsp.global("caelestia:brightnessUp"), locked)
create_bind("XF86MonBrightnessDown", hl.dsp.global("caelestia:brightnessDown"), locked)

-- Media
create_bind({ vars.kbMediaToggle, "XF86AudioPlay", "XF86AudioPause" }, hl.dsp.global("caelestia:mediaToggle"), locked)
create_bind({ vars.kbMediaNext, "XF86AudioNext" }, hl.dsp.global("caelestia:mediaNext"), locked)
create_bind({ vars.kbMediaPrev, "XF86AudioPrev" }, hl.dsp.global("caelestia:mediaPrev"), locked)
create_bind({ vars.kbMediaStop, "XF86AudioStop" }, hl.dsp.global("caelestia:mediaStop"), locked)

-- Volume
create_bind({ vars.kbVolumeMute, "XF86AudioMute" }, hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), locked)
create_bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), locked)
create_bind(
    "XF86AudioRaiseVolume",
    hl.dsp.exec_cmd(
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l " ..
        (vars.volumeMax / 100) .. " @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%+"
    ),
    locked_repeating
)
create_bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd(
        "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. vars.volumeStep .. "%-"
    ),
    locked_repeating
)

-- Sleep
create_bind(vars.kbSleep, hl.dsp.exec_cmd(vars.sleepGestureCmd), locked)

-- Clipboard and emoji picker
create_bind(vars.kbClipboard, hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard"))
create_bind(vars.kbClipboardDel, hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard -d"))
create_bind(vars.kbEmoji, hl.dsp.exec_cmd("pkill fuzzel || caelestia emoji -p"))
create_bind(
    vars.kbClipboardPasteLatest,
    hl.dsp.exec_cmd('sleep 0.5s && ydotool type -d 1 "$(cliphist list | head -1 | cliphist decode)"'),
    locked
)

-- Testing
create_bind(
    "SUPER + ALT + F12",
    hl.dsp.exec_cmd(
        "notify-send -u low -i dialog-information-symbolic 'Test notification' " ..
        [["Here's a really long message to test truncation and wrapping\nYou can middle click or flick this notification to dismiss it!"]] ..
        " -a 'Shell' -A 'Test1=I got it!' -A 'Test2=Another action'"
    )
)
