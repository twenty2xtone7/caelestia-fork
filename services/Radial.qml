pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import Caelestia.Models
import qs.components.misc
import qs.services
import qs.utils

// Configurable radial menu: one user-editable JSON file, trigonometry based
// layout, and a small action abstraction (app / command / url / caelestia).
// Profiles are supported through `menus`, so more radial menus can be added
// later without touching the UI.
Singleton {
    id: root

    readonly property string configPath: `${Paths.config}/radial.json`

    // Whole parsed config, kept as a var so the Nexus editor can mutate it
    property var config: ({})
    property string menuId: "main"

    readonly property var menu: {
        const menus = config.menus ?? {};
        return menus[root.menuId] ?? menus["main"] ?? {};
    }

    readonly property var allItems: menu.items ?? []
    readonly property var items: allItems.filter(i => i.enabled !== false)

    // Shipped defaults, so "reset" works even without a config file
    readonly property var defaultMenu: {
        return {
            radius: 130,
            startAngle: -90,
            anchor: "center",
            holdToActivate: false,
            centerAction: "close",
            items: [
                { label: "Firefox", type: "app", value: "firefox", icon: "public", key: "1" },
                { label: "Files", type: "command", value: "thunar", icon: "folder", key: "2" },
                { label: "Terminal", type: "app", value: "foot", icon: "terminal", key: "3" },
                { label: "GitHub", type: "url", value: "https://github.com", icon: "language", key: "4" },
                { label: "Screenshot", type: "caelestia", value: "screenshot", icon: "photo_camera", key: "5" },
                { label: "Record", type: "caelestia", value: "record", icon: "screen_record", key: "6" },
                { label: "Clipboard", type: "caelestia", value: "clipboard", icon: "content_paste", key: "7" },
                { label: "Night mode", type: "caelestia", value: "toggleNightMode", icon: "bedtime", key: "8" },
                { label: "Restart Caelestia", type: "caelestia", value: "restartCaelestia", icon: "refresh", key: "0" },
                { label: "Settings", type: "caelestia", value: "openNexus", icon: "settings", key: "9" }
            ]
        };
    }
    readonly property int radius: menu.radius ?? 130
    readonly property real startAngle: menu.startAngle ?? -90
    readonly property string anchor: menu.anchor ?? "center"
    readonly property bool holdToActivate: menu.holdToActivate ?? false
    readonly property string centerAction: menu.centerAction ?? "close"

    // Interaction state
    property bool open: false
    property bool holdMode: false
    property int selectedIndex: -1
    property string screenName: ""

    readonly property bool active: open

    // ---- geometry ----

    // Radial position of an item, relative to the menu origin. Angles are
    // evenly distributed from startAngle, so any item count just works.
    function offsetFor(index: int, count: int, rad: real): var {
        if (count <= 0)
            return { x: 0, y: 0 };
        const step = 360 / count;
        const angle = (root.startAngle + step * index) * Math.PI / 180;
        return {
            x: Math.cos(angle) * rad,
            y: Math.sin(angle) * rad
        };
    }

    // ---- icons ----

    function entryFor(name: string): var {
        if (!name)
            return null;
        const apps = DesktopEntries.applications.values;
        const key = name.toLowerCase();
        return apps.find(a => a.id?.toLowerCase() === key || a.name?.toLowerCase() === key) ?? null;
    }

    // Resolved icon URL for app items, through Caelestia's own icon system.
    // Returns "" when there is nothing to show, so the material fallback wins.
    function iconUrl(item: var): string {
        // An explicit "icon" in the config is a manual override: the material
        // glyph wins and the themed application icon is skipped.
        if (item?.icon)
            return "";
        const name = iconThemeName(item);
        if (!name)
            return "";
        const url = Quickshell.iconPath(name);
        return url ? url.toString() : "";
    }

    // Themed icon name (e.g. "foot", "firefox") for app items, so the
    // existing icon theme is reused instead of a second icon framework.
    function iconThemeName(item: var): string {
        if (item?.iconTheme)
            return item.iconTheme;
        if (item?.type !== "app")
            return "";
        const app = entryFor(String(item.value ?? ""));
        if (!app)
            return "";
        return String(DesktopEntries.heuristicLookup(app.name ?? app.id)?.icon ?? "");
    }

    function iconName(item: var): string {
        if (item?.icon)
            return item.icon;
        if (item?.type === "app")
            return "apps";
        if (item?.type === "command")
            return "terminal";
        if (item?.type === "url")
            return "language";
        if (item?.type === "caelestia")
            return "auto_awesome";
        return "apps";
    }

    // ---- activation keys ----

    // Canonical form for a slot key: a single upper-case digit/letter, or ""
    // when the slot has no key assigned. The key is a user-facing identifier,
    // independent of the slot's radial position.
    function normaliseKey(key: string): string {
        const k = String(key ?? "").trim().toUpperCase();
        return /^[0-9A-Z]$/.test(k) ? k : "";
    }

    function keyFor(item: var): string {
        return normaliseKey(item?.key);
    }

    // Display-list index of the enabled slot bound to `key`, or -1. Only
    // enabled slots participate, so disabled ones can never steal a keypress.
    function indexForKey(key: string): int {
        const k = normaliseKey(key);
        if (!k)
            return -1;
        return items.findIndex(it => normaliseKey(it.key) === k);
    }

    // Keys claimed by more than one enabled slot (possible in hand-edited
    // configs). The settings UI resolves these on assign; this exposes any
    // leftovers so they can be flagged instead of silently ambiguous.
    function duplicateKeys(): var {
        const seen = {};
        const dupes = [];
        for (const it of items) {
            const k = normaliseKey(it.key);
            if (!k)
                continue;
            if (seen[k] && !dupes.includes(k))
                dupes.push(k);
            seen[k] = true;
        }
        return dupes;
    }

    // Assign a key to an allItems index, stealing it from any other slot so
    // mappings stay unambiguous. Returns the displaced slot's label, or ""
    // when nothing was stolen. Empty/invalid keys just clear the slot.
    function assignKey(index: int, key: string): string {
        const k = normaliseKey(key);
        if (index < 0 || index >= allItems.length)
            return "";
        let displaced = "";
        const copy = allItems.map((it, i) => {
            if (i === index)
                return Object.assign({}, it, { key: k });
            if (k && normaliseKey(it.key) === k) {
                displaced = it.label ?? "";
                return Object.assign({}, it, { key: "" });
            }
            return it;
        });
        setItems(copy);
        return displaced;
    }

    // Keyboard entry point: press -> highlight (existing selected animation)
    // -> run via the standard dispatcher -> close. Returns true when a slot
    // matched, so the caller can consume exactly the handled input.
    function activateKey(key: string): bool {
        const idx = indexForKey(key);
        if (idx < 0)
            return false;
        selectedIndex = idx;
        activate(idx);
        return true;
    }

    // ---- actions ----

    function runItem(item: var): void {
        if (!item)
            return;

        const value = String(item.value ?? "");
        if (item.type === "app") {
            const app = entryFor(value);
            if (!app) {
                // Not a known desktop entry: treat it as a command instead
                Quickshell.execDetached(["sh", "-c", value]);
                return;
            }
            launchEntry(app);
        } else if (item.type === "command") {
            Quickshell.execDetached(["sh", "-c", value]);
        } else if (item.type === "url") {
            Quickshell.execDetached(["xdg-open", value]);
        } else if (item.type === "caelestia") {
            runCaelestiaAction(value);
        }
    }

    // Same behaviour as the launcher's app launch (Apps.launch), minus the
    // search index bookkeeping, so we don't have to import the launcher module.
    function launchEntry(app: var): void {
        // DesktopEntries entries come either wrapped (AppEntry.entry) or bare
        const entry = app.entry ?? app;
        if (entry.runInTerminal) {
            Quickshell.execDetached({
                command: [...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...entry.command],
                workingDirectory: entry.workingDirectory
            });
        } else {
            entry.execute();
        }
    }

    function runCaelestiaAction(name: string): void {
        const state = ShellState.forActive();
        const toggle = key => {
            if (state && typeof state[key] === "boolean")
                state[key] = !state[key];
        };

        switch (name) {
        case "toggleSidebar":
            toggle("sidebar");
            break;
        case "toggleDashboard":
            toggle("dashboard");
            break;
        case "toggleLauncher":
            toggle("launcher");
            break;
        case "toggleOsd":
            toggle("osd");
            break;
        case "toggleUtilities":
            toggle("utilities");
            break;
        case "toggleSession":
            toggle("session");
            break;
        case "openNexus":
            Hypr.dispatch("caelestia:nexus");
            break;
        case "screenshot":
            Quickshell.execDetached(["caelestia", "screenshot"]);
            break;
        case "clipboard":
            Hypr.dispatch("caelestia:clipboard");
            break;
        case "emoji":
            Quickshell.execDetached(["caelestia", "emoji", "-p"]);
            break;
        case "record":
            // Route through the Recorder service (not raw `caelestia record`)
            // so shell-started recordings get survivable stdio and the
            // sidebar tracking/controls stay in sync. Toggles: press again
            // to stop. `-s` includes system audio (plain `record` is
            // video-only by CLI design).
            if (Recorder.running)
                Recorder.stop();
            else
                Recorder.start(["-s"]);
            break;
        case "toggleGameMode":
            GameMode.enabled = !GameMode.enabled;
            break;
        case "toggleNightMode":
            Night.toggle();
            break;
        case "randomWallpaper":
            Wallpapers.setRandom();
            break;
        case "toggleDarkTheme":
            Colours.setMode(Colours.light ? "dark" : "light");
            break;
        case "lockScreen":
            SessionManager.lockRequested();
            break;
        case "logout":
            SessionManager.logout();
            break;
        case "suspend":
            SessionManager.suspend();
            break;
        case "poweroff":
            SessionManager.poweroff();
            break;
        case "reboot":
            SessionManager.reboot();
            break;
        case "restartCaelestia":
            restartShell();
            break;
        }
    }

    function restartShell(): void {
        // Spawn new instance first, then kill current one
        Quickshell.execDetached(["quickshell", "-c", "caelestia", "-d"]);
        restartTimer.running = true;
    }

    function activate(index: int): void {
        const item = items[index];
        hide();
        if (!item)
            return;
        // Run after the close animation has been kicked off
        closeTimer.item = item;
        closeTimer.running = true;
    }

    function activateSelected(): void {
        if (selectedIndex >= 0)
            activate(selectedIndex);
        else
            hide();
    }

    function activateCenter(): void {
        if (centerAction === "close" || !centerAction) {
            hide();
            return;
        }
        hide();
        centerTimer.action = centerAction;
        centerTimer.running = true;
    }

    // ---- open / close ----

    function show(screen: string, asHold: bool): void {
        screenName = screen ?? screenName;
        holdMode = asHold ?? holdToActivate;
        selectedIndex = -1;
        open = true;
    }

    function toggle(): void {
        if (open) {
            hide();
        } else {
            show("", holdToActivate);
        }
    }

    function hide(): void {
        open = false;
        holdMode = false;
        selectedIndex = -1;
    }

    // ---- config ----

    function loadConfig(data: string): void {
        if (!data || data.trim().length === 0)
            return;
        try {
            config = JSON.parse(data);
        } catch (e) {
            console.warn("Radial: invalid config JSON", e);
        }
    }

    function saveConfig(): void {
        saver.environment = {
            RADIAL_PATH: root.configPath,
            RADIAL_JSON: JSON.stringify(root.config, null, 4)
        };
        saver.running = true;
    }

    // Mutate a menu field and persist
    function setMenuValue(key: string, value: var): void {
        const menus = Object.assign({}, config.menus ?? {});
        menus[root.menuId] = Object.assign({}, menus[root.menuId] ?? {}, { [key]: value });
        config = Object.assign({}, config, { menus: menus });
        saveConfig();
    }

    function resetDefaults(): void {
        const menus = Object.assign({}, config.menus ?? {});
        const d = defaultMenu;
        menus[root.menuId] = {
            radius: d.radius,
            startAngle: d.startAngle,
            anchor: d.anchor,
            holdToActivate: d.holdToActivate,
            centerAction: d.centerAction,
            items: d.items.map(i => Object.assign({}, i))
        };
        config = Object.assign({}, config, { menus: menus });
        saveConfig();
    }

    // NOTE: all of these take indices into the FULL item list (`allItems`),
    // matching what the Nexus editor and the IPC interface show. Disabled
    // items are part of the list, so no display-index remapping is needed
    // (and remapping here is what used to toggle/move/remove the wrong item
    // whenever a disabled entry preceded the target).
    function setItems(newItems: var): void {
        setMenuValue("items", newItems);
    }

    function setItem(index: int, key: string, value: var): void {
        if (index < 0 || index >= allItems.length)
            return;
        // IPC delivers everything as strings; coerce so scripts can write
        // real booleans for the switch.
        if (key === "enabled" && typeof value === "string")
            value = value.toLowerCase() === "true";
        setItems(allItems.map((it, i) => i === index ? Object.assign({}, it, { [key]: value }) : it));
    }

    function addItem(): void {
        const copy = [...allItems, { label: Tr.tr("New item"), type: "command", value: "", icon: "terminal", enabled: true }];
        setItems(copy);
    }

    function moveItem(from: int, to: int): void {
        if (from === to || from < 0 || to < 0 || from >= allItems.length || to >= allItems.length)
            return;
        const copy = [...allItems];
        const [moved] = copy.splice(from, 1);
        copy.splice(to, 0, moved);
        setItems(copy);
    }

    function removeItem(index: int): void {
        if (index < 0 || index >= allItems.length)
            return;
        setItems(allItems.filter((it, i) => i !== index));
    }

    // ---- deferred runners (run once the menu is closed) ----

    Timer {
        id: closeTimer

        property var item: null
        interval: 120
        onTriggered: {
            const it = item;
            item = null;
            root.runItem(it);
        }
    }

    Timer {
        id: centerTimer

        property string action: ""
        interval: 120
        onTriggered: {
            const a = action;
            action = "";
            root.runCaelestiaAction(a);
        }
    }

    Timer {
        id: restartTimer

        interval: 200
        onTriggered: {
            Qt.quit();
        }
    }

    // Writes the config file atomically. The JSON travels through an env var
    // so no shell quoting is involved.
    Process {
        id: saver

        command: ["python3", "-c", "import json,os,sys\np = os.environ['RADIAL_PATH']\nd = json.loads(os.environ['RADIAL_JSON'])\nos.makedirs(os.path.dirname(p), exist_ok=True)\ntmp = p + '.tmp'\nwith open(tmp, 'w') as f:\n    json.dump(d, f, indent=4)\n    f.write('\\n')\nos.replace(tmp, p)"]
    }

    FileView {
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.loadConfig(text())
    }

    // ---- shortcuts & ipc ----

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "radial"
        description: "Open the radial menu"
        onPressed: root.show("", root.holdToActivate)
        onReleased: {
            if (root.open && root.holdMode)
                root.activateSelected();
        }
    }

    IpcHandler {
        function open(): void {
            root.show("", false);
        }

        function toggle(): void {
            root.toggle();
        }

        function close(): void {
            root.hide();
        }

        function activate(index: int): void {
            root.activate(index);
        }

        function items(): string {
            // Indices match setitem/removeitem (full list, including disabled).
            return root.allItems.map((it, i) => `${i}:${it.label ?? ""}:${it.enabled === false ? "disabled" : "enabled"}`).join("\n");
        }

        function reset(): void {
            root.resetDefaults();
        }

        function setitem(index: int, key: string, value: string): void {
            root.setItem(index, key, value);
        }

        function additem(): void {
            root.addItem();
        }

        function removeitem(index: int): void {
            root.removeItem(index);
        }

        function debug(): string {
            return root.allItems.map((it, i) => {
                const app = root.entryFor(String(it.value ?? ""));
                return `${i} ${it.label} type=${it.type} enabled=${it.enabled === false ? "no" : "yes"} app=${app ? "yes" : "no"} id=${app?.id ?? "-"} name=${app?.name ?? "-"} icon=${root.iconThemeName(it)}`;
            }).join("\n");
        }

        target: "radial"
    }
}
