local vars = require("variables")

-- Themes
hl.env("QT_QPA_PLATFORMTHEME", "qtengine")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("XCURSOR_THEME", vars.cursorTheme)
hl.env("XCURSOR_SIZE", vars.cursorSize)

-- Toolkit backends
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland,x11,windows")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- XDG specifications
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Others
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")

-- Hindsight (opencode memory) -> local 9router OpenAI-compatible gateway
hl.env("HINDSIGHT_API_LLM_PROVIDER", "openai")
hl.env("HINDSIGHT_API_LLM_BASE_URL", "http://127.0.0.1:20128/v1")
hl.env("HINDSIGHT_API_LLM_API_KEY", "sk-d6a9751fac23b928-qdogm9-8f5733f3")
hl.env("HINDSIGHT_API_LLM_MODEL", "22xt1")
