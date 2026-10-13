pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    // ── Master toggle ───────────────────────────────────────────────────────
    property bool enabled: true

    // ── Material ────────────────────────────────────────────────────────────
    property real opacity: 0.85
    property real tint: 0.3
    property real saturation: 1.1
    property real brightness: 1.0
    property real contrast: 1.0

    // ── Depth ───────────────────────────────────────────────────────────────
    property real borderOpacity: 0.15
    property real highlightOpacity: 0.08
    property bool innerHighlight: true
    property real shadowOpacity: 0.7
    property real shadowBlur: 15

    // ── Shape ─────────────────────────────────────────────────────────────────
    property real cornerRadius: 28
    property real cardRadius: 18
    property real controlRadius: 12
    property real popupRadius: 20

    // ── Interaction / Motion ──────────────────────────────────────────────────
    property real hoverIntensity: 0.5
    property real pressIntensity: 0.3
    property real accentInfluence: 0.2
    property real animationIntensity: 0.5
    property real animationSpeed: 1.0

    // ── Presets ───────────────────────────────────────────────────────────────
    property string activePreset: "Default"
    property var userPresets: ({})  // name → preset data object

    // Signal emitted after every property change so components can batch updates.
    signal changed()

    // ── Component override storage ────────────────────────────────────────────
    // Sparse per-component overrides. Each entry is an object with a subset of
    // the above properties, keyed by component name.
    property var overrides: ({
        bar: {},
        launcher: {},
        sidebar: {},
        dashboard: {},
        notifications: {},
        osd: {},
        menus: {},
        dialogs: {}
    })

    readonly property var componentNames: ["bar", "launcher", "sidebar", "dashboard", "notifications", "osd", "menus", "dialogs"]

    // ── Built-in presets ──────────────────────────────────────────────────────
    function presetData(name: string): var {
        const presets = {
            "Default": {
                opacity: 0.85, tint: 0.3, saturation: 1.1, brightness: 1.0, contrast: 1.0,
                borderOpacity: 0.15, highlightOpacity: 0.08, innerHighlight: true,
                shadowOpacity: 0.7, shadowBlur: 15,
                cornerRadius: 28, cardRadius: 18, controlRadius: 12, popupRadius: 20,
                hoverIntensity: 0.5, pressIntensity: 0.3, accentInfluence: 0.2,
                animationIntensity: 0.5, animationSpeed: 1.0
            },
            "Clear Glass": {
                opacity: 0.55, tint: 0.15, saturation: 1.0, brightness: 1.0, contrast: 1.0,
                borderOpacity: 0.08, highlightOpacity: 0.06, innerHighlight: true,
                shadowOpacity: 0.4, shadowBlur: 8,
                cornerRadius: 28, cardRadius: 18, controlRadius: 12, popupRadius: 20,
                hoverIntensity: 0.4, pressIntensity: 0.25, accentInfluence: 0.15,
                animationIntensity: 0.5, animationSpeed: 1.0
            },
            "Frosted Glass": {
                opacity: 0.92, tint: 0.45, saturation: 1.0, brightness: 1.02, contrast: 1.05,
                borderOpacity: 0.22, highlightOpacity: 0.1, innerHighlight: true,
                shadowOpacity: 0.55, shadowBlur: 20,
                cornerRadius: 28, cardRadius: 20, controlRadius: 14, popupRadius: 22,
                hoverIntensity: 0.55, pressIntensity: 0.32, accentInfluence: 0.25,
                animationIntensity: 0.5, animationSpeed: 1.0
            },
            "Deep Glass": {
                opacity: 0.96, tint: 0.6, saturation: 0.95, brightness: 0.95, contrast: 1.1,
                borderOpacity: 0.28, highlightOpacity: 0.06, innerHighlight: false,
                shadowOpacity: 0.75, shadowBlur: 24,
                cornerRadius: 24, cardRadius: 16, controlRadius: 10, popupRadius: 18,
                hoverIntensity: 0.6, pressIntensity: 0.35, accentInfluence: 0.18,
                animationIntensity: 0.45, animationSpeed: 1.05
            },
            "Acrylic": {
                opacity: 0.9, tint: 0.5, saturation: 1.05, brightness: 1.0, contrast: 1.0,
                borderOpacity: 0.18, highlightOpacity: 0.09, innerHighlight: true,
                shadowOpacity: 0.6, shadowBlur: 18,
                cornerRadius: 16, cardRadius: 12, controlRadius: 10, popupRadius: 14,
                hoverIntensity: 0.5, pressIntensity: 0.28, accentInfluence: 0.2,
                animationIntensity: 0.4, animationSpeed: 0.95
            },
            "Liquid": {
                opacity: 0.8, tint: 0.35, saturation: 1.15, brightness: 1.0, contrast: 1.0,
                borderOpacity: 0.12, highlightOpacity: 0.1, innerHighlight: true,
                shadowOpacity: 0.5, shadowBlur: 22,
                cornerRadius: 32, cardRadius: 22, controlRadius: 14, popupRadius: 24,
                hoverIntensity: 0.65, pressIntensity: 0.35, accentInfluence: 0.3,
                animationIntensity: 0.75, animationSpeed: 1.05
            },
            "Minimal": {
                opacity: 0.98, tint: 0.1, saturation: 1.0, brightness: 1.0, contrast: 1.0,
                borderOpacity: 0.05, highlightOpacity: 0.04, innerHighlight: false,
                shadowOpacity: 0.3, shadowBlur: 6,
                cornerRadius: 16, cardRadius: 12, controlRadius: 8, popupRadius: 12,
                hoverIntensity: 0.35, pressIntensity: 0.2, accentInfluence: 0.1,
                animationIntensity: 0.25, animationSpeed: 0.9
            }
        };
        if (presets[name])
            return presets[name];
        if (root.userPresets && root.userPresets[name])
            return root.userPresets[name];
        return presets["Default"];
    }

    readonly property list<string> builtInPresets: ["Default", "Clear Glass", "Frosted Glass", "Deep Glass", "Acrylic", "Liquid", "Minimal"]

    // ── Override helpers ──────────────────────────────────────────────────────
    function overrideFor(component: string): var {
        return root.overrides[component] ?? {};
    }

    function effectiveValue(prop: string, component: string): var {
        const over = root.overrides[component];
        if (over && Object.prototype.hasOwnProperty.call(over, prop))
            return over[prop];
        return root[prop];
    }

    function setOverride(component: string, prop: string, value: var): void {
        if (!Object.prototype.hasOwnProperty.call(root.overrides, component))
            return;
        const clone = Object.assign({}, root.overrides);
        const next = Object.assign({}, clone[component] || {});
        next[prop] = value;
        clone[component] = next;
        root.overrides = clone;
        scheduleSave();
    }

    function clearOverride(component: string, prop: string): void {
        const clone = Object.assign({}, root.overrides);
        const next = Object.assign({}, clone[component] || {});
        delete next[prop];
        clone[component] = next;
        root.overrides = clone;
        scheduleSave();
    }

    function useGlobalForComponent(component: string): void {
        const clone = Object.assign({}, root.overrides);
        clone[component] = {};
        root.overrides = clone;
        scheduleSave();
    }

    function componentUsesGlobal(component: string): bool {
        const comp = root.overrides[component];
        return !comp || Object.keys(comp).length === 0;
    }

    // ── Shape helpers ─────────────────────────────────────────────────────────
    function radius(group: string): real {
        switch (group) {
        case "major":
        case "surface":
        case "panel":
        case "corner":
            return root.cornerRadius;
        case "card":
            return root.cardRadius;
        case "control":
        case "button":
            return root.controlRadius;
        case "popup":
        case "menu":
        case "dialog":
            return root.popupRadius;
        case "full":
        case "pill":
            return 9999;
        }
        return root.cornerRadius;
    }

    // ── Apply preset ──────────────────────────────────────────────────────────
    function applyPreset(name: string): void {
        const data = Object.assign({}, root.presetData("Default"), root.presetData(name) || {});
        applying = true;
        root.enabled = true;
        root.opacity = root.clampNum(data.opacity, 0.1, 1.0, 0.85);
        root.tint = root.clampNum(data.tint, 0, 1, 0.3);
        root.saturation = root.clampNum(data.saturation, 0, 2, 1.1);
        root.brightness = root.clampNum(data.brightness, 0.5, 1.5, 1.0);
        root.contrast = root.clampNum(data.contrast, 0.5, 1.5, 1.0);
        root.borderOpacity = root.clampNum(data.borderOpacity, 0, 1, 0.15);
        root.highlightOpacity = root.clampNum(data.highlightOpacity, 0, 1, 0.08);
        root.innerHighlight = root.clampBool(data.innerHighlight, true);
        root.shadowOpacity = root.clampNum(data.shadowOpacity, 0, 1, 0.7);
        root.shadowBlur = root.clampNum(data.shadowBlur, 0, 48, 15);
        root.cornerRadius = root.clampNum(data.cornerRadius, 0, 48, 28);
        root.cardRadius = root.clampNum(data.cardRadius, 0, 48, 18);
        root.controlRadius = root.clampNum(data.controlRadius, 0, 48, 12);
        root.popupRadius = root.clampNum(data.popupRadius, 0, 48, 20);
        root.hoverIntensity = root.clampNum(data.hoverIntensity, 0, 1, 0.5);
        root.pressIntensity = root.clampNum(data.pressIntensity, 0, 1, 0.3);
        root.accentInfluence = root.clampNum(data.accentInfluence, 0, 1, 0.2);
        root.animationIntensity = root.clampNum(data.animationIntensity, 0, 1, 0.5);
        root.animationSpeed = root.clampNum(data.animationSpeed, 0.25, 3, 1.0);
        root.activePreset = name;
        applying = false;
        scheduleSave();
        root.changed();
    }

    // ── Reset ─────────────────────────────────────────────────────────────────
    function resetDefaults(): void {
        root.applyPreset("Default");
        root.userPresets = {};
        root.overrides = {
            bar: {}, launcher: {}, sidebar: {}, dashboard: {},
            notifications: {}, osd: {}, menus: {}, dialogs: {}
        };
        root.activePreset = "Default";
        scheduleSave();
        root.changed();
    }

    function resetSection(section: string): void {
        const def = root.presetData("Default");
        applying = true;
        switch (section) {
        case "material":
            root.opacity = def.opacity;
            root.tint = def.tint;
            root.saturation = def.saturation;
            root.brightness = def.brightness;
            root.contrast = def.contrast;
            break;
        case "depth":
            root.borderOpacity = def.borderOpacity;
            root.highlightOpacity = def.highlightOpacity;
            root.innerHighlight = def.innerHighlight;
            root.shadowOpacity = def.shadowOpacity;
            root.shadowBlur = def.shadowBlur;
            break;
        case "shape":
            root.cornerRadius = def.cornerRadius;
            root.cardRadius = def.cardRadius;
            root.controlRadius = def.controlRadius;
            root.popupRadius = def.popupRadius;
            break;
        case "motion":
            root.hoverIntensity = def.hoverIntensity;
            root.pressIntensity = def.pressIntensity;
            root.accentInfluence = def.accentInfluence;
            root.animationIntensity = def.animationIntensity;
            root.animationSpeed = def.animationSpeed;
            break;
        }
        root.activePreset = "Custom";
        applying = false;
        scheduleSave();
        root.changed();
    }

    // ── User presets ──────────────────────────────────────────────────────────
    function saveAsPreset(name: string): void {
        if (!name || typeof name !== "string")
            return;
        const clone = Object.assign({}, root.userPresets);
        clone[name] = root.toJson();
        root.userPresets = clone;
        root.activePreset = name;
        scheduleSave();
    }

    function deleteUserPreset(name: string): void {
        const clone = Object.assign({}, root.userPresets);
        delete clone[name];
        root.userPresets = clone;
        if (root.activePreset === name)
            root.activePreset = "Custom";
        scheduleSave();
    }

    // ── Import / Export ───────────────────────────────────────────────────────
    function exportConfig(): string {
        return JSON.stringify(root.toJson(), null, 4);
    }

    function importConfig(text: string): bool {
        try {
            const data = JSON.parse(text);
            if (!data || typeof data !== "object")
                return false;
            root.applyData(data);
            return true;
        } catch (e) {
            console.warn("LiquidGlass: failed to import config:", e);
            return false;
        }
    }

    // ── Persistence ───────────────────────────────────────────────────────────
    property bool applying: false
    property bool loaded: false

    readonly property list<string> presetProperties: [
        "enabled", "opacity", "tint", "saturation", "brightness", "contrast",
        "borderOpacity", "highlightOpacity", "innerHighlight", "shadowOpacity", "shadowBlur",
        "cornerRadius", "cardRadius", "controlRadius", "popupRadius",
        "hoverIntensity", "pressIntensity", "accentInfluence", "animationIntensity", "animationSpeed"
    ]

    function toJson(): var {
        return {
            enabled: root.enabled,
            opacity: root.opacity,
            tint: root.tint,
            saturation: root.saturation,
            brightness: root.brightness,
            contrast: root.contrast,
            borderOpacity: root.borderOpacity,
            highlightOpacity: root.highlightOpacity,
            innerHighlight: root.innerHighlight,
            shadowOpacity: root.shadowOpacity,
            shadowBlur: root.shadowBlur,
            cornerRadius: root.cornerRadius,
            cardRadius: root.cardRadius,
            controlRadius: root.controlRadius,
            popupRadius: root.popupRadius,
            hoverIntensity: root.hoverIntensity,
            pressIntensity: root.pressIntensity,
            accentInfluence: root.accentInfluence,
            animationIntensity: root.animationIntensity,
            animationSpeed: root.animationSpeed,
            activePreset: root.activePreset,
            userPresets: root.userPresets,
            overrides: root.overrides
        };
    }

    function clampNum(v: var, lo: real, hi: real, fallback: real): real {
        const n = Number(v);
        if (isNaN(n)) return fallback;
        return Math.min(hi, Math.max(lo, n));
    }

    function clampBool(v: var, fallback: bool): bool {
        return typeof v === "boolean" ? v : fallback;
    }

    function applyData(data: var): void {
        if (!data || typeof data !== "object") return;

        applying = true;

        root.enabled = root.clampBool(data.enabled, true);
        root.opacity = root.clampNum(data.opacity, 0.1, 1.0, 0.85);
        root.tint = root.clampNum(data.tint, 0, 1, 0.3);
        root.saturation = root.clampNum(data.saturation, 0, 2, 1.1);
        root.brightness = root.clampNum(data.brightness, 0.5, 1.5, 1.0);
        root.contrast = root.clampNum(data.contrast, 0.5, 1.5, 1.0);

        root.borderOpacity = root.clampNum(data.borderOpacity, 0, 1, 0.15);
        root.highlightOpacity = root.clampNum(data.highlightOpacity, 0, 1, 0.08);
        root.innerHighlight = root.clampBool(data.innerHighlight, true);
        root.shadowOpacity = root.clampNum(data.shadowOpacity, 0, 1, 0.7);
        root.shadowBlur = root.clampNum(data.shadowBlur, 0, 48, 15);

        root.cornerRadius = root.clampNum(data.cornerRadius, 0, 48, 28);
        root.cardRadius = root.clampNum(data.cardRadius, 0, 48, 18);
        root.controlRadius = root.clampNum(data.controlRadius, 0, 48, 12);
        root.popupRadius = root.clampNum(data.popupRadius, 0, 48, 20);

        root.hoverIntensity = root.clampNum(data.hoverIntensity, 0, 1, 0.5);
        root.pressIntensity = root.clampNum(data.pressIntensity, 0, 1, 0.3);
        root.accentInfluence = root.clampNum(data.accentInfluence, 0, 1, 0.2);
        root.animationIntensity = root.clampNum(data.animationIntensity, 0, 1, 0.5);
        root.animationSpeed = root.clampNum(data.animationSpeed, 0.25, 3, 1.0);

        root.activePreset = typeof data.activePreset === "string" ? data.activePreset : "Default";

        if (data.userPresets && typeof data.userPresets === "object" && !Array.isArray(data.userPresets))
            root.userPresets = data.userPresets;
        else
            root.userPresets = {};

        if (data.overrides && typeof data.overrides === "object" && !Array.isArray(data.overrides)) {
            const merged = {
                bar: {}, launcher: {}, sidebar: {}, dashboard: {},
                notifications: {}, osd: {}, menus: {}, dialogs: {}
            };
            for (const key of Object.keys(merged)) {
                if (data.overrides[key] && typeof data.overrides[key] === "object")
                    merged[key] = data.overrides[key];
            }
            root.overrides = merged;
        } else {
            root.overrides = {
                bar: {}, launcher: {}, sidebar: {}, dashboard: {},
                notifications: {}, osd: {}, menus: {}, dialogs: {}
            };
        }

        applying = false;
        root.changed();
    }

    function scheduleSave(): void {
        if (applying || !loaded) return;
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: storage.setText(JSON.stringify(root.toJson(), null, 4))
    }

    // Save on any property change.
    onEnabledChanged: scheduleSave()
    onOpacityChanged: { scheduleSave(); changed(); }
    onTintChanged: { scheduleSave(); changed(); }
    onSaturationChanged: { scheduleSave(); changed(); }
    onBrightnessChanged: { scheduleSave(); changed(); }
    onContrastChanged: { scheduleSave(); changed(); }
    onBorderOpacityChanged: { scheduleSave(); changed(); }
    onHighlightOpacityChanged: { scheduleSave(); changed(); }
    onInnerHighlightChanged: { scheduleSave(); changed(); }
    onShadowOpacityChanged: { scheduleSave(); changed(); }
    onShadowBlurChanged: { scheduleSave(); changed(); }
    onCornerRadiusChanged: { scheduleSave(); changed(); }
    onCardRadiusChanged: { scheduleSave(); changed(); }
    onControlRadiusChanged: { scheduleSave(); changed(); }
    onPopupRadiusChanged: { scheduleSave(); changed(); }
    onHoverIntensityChanged: { scheduleSave(); changed(); }
    onPressIntensityChanged: { scheduleSave(); changed(); }
    onAccentInfluenceChanged: { scheduleSave(); changed(); }
    onAnimationIntensityChanged: { scheduleSave(); changed(); }
    onAnimationSpeedChanged: { scheduleSave(); changed(); }
    onActivePresetChanged: scheduleSave()
    onUserPresetsChanged: scheduleSave()
    onOverridesChanged: scheduleSave()

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/liquid-glass.json`
        onLoaded: {
            try {
                root.applyData(JSON.parse(text()));
            } catch (e) {
                console.warn("LiquidGlass: failed to parse liquid-glass.json, using defaults:", e);
            }
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify(root.toJson(), null, 4)));
            root.loaded = true;
        }
    }
}
