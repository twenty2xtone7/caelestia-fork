pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Dyn-Lyrics panel settings.
//
// Caelestia's own config (`GlobalConfig`) is a compiled C++ schema: every
// section is a typed node and unknown keys are rejected as diagnostics, so a
// new `dynLyrics` section cannot be added from QML. This singleton therefore
// uses the same persistence mechanism the shell already uses for its other
// QML-owned state (LiquidGlass → liquid-glass.json, BarState → bar-position.txt):
// a FileView-backed JSON file under `Paths.state`, with clamped defaults.
Singleton {
    id: root

    // ── Appearance ───────────────────────────────────────────────────────────
    // Only the top edge is supported by the reveal architecture; the anchor
    // picks the horizontal placement along that edge.
    property string anchorPosition: "top-center" // top-center | top-left | top-right
    property bool autoWidth: true
    property string widthMode: "autoLimits" // fixed | auto | autoLimits
    property int minWidth: 180
    property int maxWidth: 360
    property int fixedWidth: 360
    property int expandedHeight: 36
    property int collapsedHeight: 0
    property int horizontalPadding: 16
    property int cornerRadius: 18
    property int horizontalOffset: 0
    property bool resizeAnimation: true
    property int resizeDuration: 200
    property string resizeEasing: "emphasized"

    // ── Panel animation ──────────────────────────────────────────────────────
    property bool panelAnimationEnabled: true
    property int expansionDuration: 350
    property int collapseDuration: 250
    property int animationDelay: 0
    property string easing: "expressiveDefaultSpatial"
    property int contentRevealDelay: 60
    property bool contentFade: true
    property int contentSlideDistance: 10

    // ── Lyrics animation ─────────────────────────────────────────────────────
    property bool lyricsAnimationEnabled: true
    property string animationType: "slideFade" // slide | fade | slideFade
    property string direction: "left" // left | right | up | down
    property int transitionDuration: 250
    property int transitionDelay: 0
    property int slideDistance: 0 // 0 = one panel width
    property string lyricEasing: "emphasized"
    property bool animateFirstLyric: false
    property bool resetAnimationOnTrackChange: true

    // ── Typography ───────────────────────────────────────────────────────────
    property string fontFamily: ""
    property int fontSize: 0 // 0 = theme default
    property int fontWeight: 400
    property string textColor: ""
    property real textOpacity: 1
    property string textAlignment: "center" // left | center | right
    property int lineSpacing: 0
    property bool textShadow: false
    property bool showArtist: false
    property bool showTrackTitle: false
    property bool showAlbum: false

    // ── Lyrics behaviour ─────────────────────────────────────────────────────
    property int syncOffset: 0 // ms, added on top of the backend timestamps
    property bool showPreviousAndNext: false
    property string fallbackText: ""
    property bool hidePanelWhenLyricsUnavailable: false

    // ── Advanced ─────────────────────────────────────────────────────────────
    property bool debugMode: false
    property bool showLyricIndex: true
    property bool showPlaybackPosition: true
    property bool showEffectiveSyncOffset: true
    property bool pauseAnimationsWhenHidden: true
    property bool reduceAnimations: false

    // ── Option lists (shared with the Nexus pages) ────────────────────────────
    readonly property var anchorPositions: ["top-center", "top-left", "top-right"]
    readonly property var widthModes: ["fixed", "auto", "autoLimits"]
    readonly property var animationTypes: ["slide", "fade", "slideFade"]
    readonly property var directions: ["left", "right", "up", "down"]
    readonly property var alignments: ["left", "center", "right"]
    // Curves resolved against Tokens.anim by the consumer.
    readonly property var easingTypes: ["standard", "standardAccel", "standardDecel", "emphasized", "emphasizedAccel", "emphasizedDecel", "expressiveFastSpatial", "expressiveDefaultSpatial", "expressiveSlowSpatial"]

    // ── Persistence ──────────────────────────────────────────────────────────
    property bool applying: false
    property bool loaded: false

    readonly property var defaults: ({
        anchorPosition: "top-center",
        autoWidth: true,
        widthMode: "autoLimits",
        minWidth: 180,
        maxWidth: 360,
        fixedWidth: 360,
        expandedHeight: 36,
        collapsedHeight: 0,
        horizontalPadding: 16,
        cornerRadius: 18,
        horizontalOffset: 0,
        resizeAnimation: true,
        resizeDuration: 200,
        resizeEasing: "emphasized",
        panelAnimationEnabled: true,
        expansionDuration: 350,
        collapseDuration: 250,
        animationDelay: 0,
        easing: "expressiveDefaultSpatial",
        contentRevealDelay: 60,
        contentFade: true,
        contentSlideDistance: 10,
        lyricsAnimationEnabled: true,
        animationType: "slideFade",
        direction: "left",
        transitionDuration: 250,
        transitionDelay: 0,
        slideDistance: 0,
        lyricEasing: "emphasized",
        animateFirstLyric: false,
        resetAnimationOnTrackChange: true,
        fontFamily: "",
        fontSize: 0,
        fontWeight: 400,
        textColor: "",
        textOpacity: 1,
        textAlignment: "center",
        lineSpacing: 0,
        textShadow: false,
        showArtist: false,
        showTrackTitle: false,
        showAlbum: false,
        syncOffset: 0,
        showPreviousAndNext: false,
        fallbackText: "",
        hidePanelWhenLyricsUnavailable: false,
        debugMode: false,
        showLyricIndex: true,
        showPlaybackPosition: true,
        showEffectiveSyncOffset: true,
        pauseAnimationsWhenHidden: true,
        reduceAnimations: false
    })

    readonly property var stringKeys: ["anchorPosition", "widthMode", "resizeEasing", "easing", "animationType", "direction", "lyricEasing", "fontFamily", "textColor", "textAlignment", "fallbackText"]
    readonly property var boolKeys: ["autoWidth", "resizeAnimation", "panelAnimationEnabled", "contentFade", "lyricsAnimationEnabled", "animateFirstLyric", "resetAnimationOnTrackChange", "textShadow", "showArtist", "showTrackTitle", "showAlbum", "showPreviousAndNext", "hidePanelWhenLyricsUnavailable", "debugMode", "showLyricIndex", "showPlaybackPosition", "showEffectiveSyncOffset", "pauseAnimationsWhenHidden", "reduceAnimations"]
    readonly property var numberKeys: ["minWidth", "maxWidth", "fixedWidth", "expandedHeight", "collapsedHeight", "horizontalPadding", "cornerRadius", "horizontalOffset", "resizeDuration", "expansionDuration", "collapseDuration", "animationDelay", "contentRevealDelay", "contentSlideDistance", "transitionDuration", "transitionDelay", "slideDistance", "fontSize", "fontWeight", "textOpacity", "lineSpacing", "syncOffset"]

    // Ranges double as validation: everything is clamped on load and on set.
    readonly property var ranges: ({
        minWidth: [40, 2000],
        maxWidth: [40, 2000],
        fixedWidth: [40, 2000],
        expandedHeight: [16, 400],
        collapsedHeight: [0, 400],
        horizontalPadding: [0, 64],
        cornerRadius: [0, 64],
        horizontalOffset: [-500, 500],
        resizeDuration: [0, 2000],
        expansionDuration: [0, 2000],
        collapseDuration: [0, 2000],
        animationDelay: [0, 2000],
        contentRevealDelay: [0, 2000],
        contentSlideDistance: [0, 200],
        transitionDuration: [0, 2000],
        transitionDelay: [0, 2000],
        slideDistance: [0, 2000],
        fontSize: [0, 48],
        fontWeight: [100, 900],
        textOpacity: [0, 1],
        lineSpacing: [0, 48],
        syncOffset: [-5000, 5000]
    })

    function clampNum(v: var, lo: real, hi: real, fallback: real): real {
        const n = Number(v);
        if (isNaN(n))
            return fallback;
        return Math.min(hi, Math.max(lo, n));
    }

    function clampBool(v: var, fallback: bool): bool {
        return typeof v === "boolean" ? v : fallback;
    }

    function clampString(v: var, allowed: var, fallback: string): string {
        return typeof v === "string" && allowed.indexOf(v) !== -1 ? v : fallback;
    }

    function toJson(): var {
        const out = {};
        for (const k of root.stringKeys)
            out[k] = root[k];
        for (const k of root.boolKeys)
            out[k] = root[k];
        for (const k of root.numberKeys)
            out[k] = root[k];
        return out;
    }

    function applyData(data: var): void {
        if (!data || typeof data !== "object")
            return;
        root.applying = true;

        const d = root.defaults;
        const allowed = {
            anchorPosition: root.anchorPositions,
            widthMode: root.widthModes,
            animationType: root.animationTypes,
            direction: root.directions,
            textAlignment: root.alignments
        };

        for (const k of root.boolKeys)
            root[k] = root.clampBool(data[k], d[k]);
        for (const k of root.numberKeys) {
            const r = root.ranges[k] ?? [0, 0];
            root[k] = root.clampNum(data[k], r[0], r[1], d[k]);
        }
        for (const k of root.stringKeys) {
            if (allowed[k])
                root[k] = root.clampString(data[k], allowed[k], d[k]);
            else if (typeof data[k] === "string")
                root[k] = data[k];
        }

        // Cross-field validation.
        if (root.minWidth > root.maxWidth)
            root.minWidth = root.maxWidth;

        root.applying = false;
    }

    function resetSettings(): void {
        root.applyData(root.defaults);
        scheduleSave();
    }

    function scheduleSave(): void {
        if (root.applying || !root.loaded)
            return;
        saveTimer.restart();
    }

    // Any property change reshapes this string, so a single handler covers the
    // whole settings surface without 50 `onXChanged` blocks.
    readonly property string stateKey: JSON.stringify(root.toJson())
    onStateKeyChanged: scheduleSave()

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: storage.setText(JSON.stringify(root.toJson(), null, 4))
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/dyn-lyrics.json`
        onLoaded: {
            try {
                root.applyData(JSON.parse(text()));
            } catch (e) {
                console.warn("DynLyricsConfig: failed to parse dyn-lyrics.json, using defaults:", e);
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
