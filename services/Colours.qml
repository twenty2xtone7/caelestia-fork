pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Images
import qs.services
import qs.utils

Singleton {
    id: root

    property bool showPreview
    property string scheme
    property string flavour
    // Last committed (non-preview) scheme payload. The wallpaper service
    // restores terminal colors from this when a preview is dismissed.
    property string committedColoursJson: ""
    readonly property bool light: showPreview ? previewLight : currentLight
    property bool currentLight
    property bool previewLight
    readonly property M3Palette palette: showPreview ? preview : (RainbowAnimator.enabled ? rainbowPalette : current)
    readonly property M3TPalette tPalette: M3TPalette {}
    readonly property M3Palette current: M3Palette {}
    readonly property M3Palette preview: M3Palette {}
    readonly property M3Palette rainbowPalette: M3RainbowPalette {}
    readonly property Transparency transparency: Transparency {}
    readonly property alias wallLuminance: analyser.luminance

    property bool cooldownPending
    property real lastBaseTransparency

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

    // Scheme colour + Liquid Glass material parameters → final glass fill.
    function glassSurface(): color {
        const c = root.layer(root.palette.m3surface, 0);
        if (!LiquidGlass.enabled)
            return c;

        const tinted = Qt.tint(c, Qt.alpha(root.palette.m3primary, LiquidGlass.tint * 0.4));
        const sat = Math.max(0, Math.min(1, tinted.hslSaturation * LiquidGlass.saturation));
        const lit = Math.max(0, Math.min(1, 0.5 + (tinted.hslLightness * LiquidGlass.brightness - 0.5) * LiquidGlass.contrast));
        return Qt.hsla(tinted.hslHue, sat, lit, c.a);
    }

    readonly property color glassFill: {
        LiquidGlass.enabled;
        LiquidGlass.opacity;
        LiquidGlass.tint;
        LiquidGlass.saturation;
        LiquidGlass.brightness;
        LiquidGlass.contrast;
        root.palette.m3surface;
        root.palette.m3primary;
        return root.glassSurface();
    }

    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1);
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    function load(data: string, isPreview: bool): void {
        const colours = isPreview ? preview : current;
        let scheme;
        try {
            scheme = JSON.parse(data);
        } catch (e) {
            console.warn("[Colours] invalid colour payload, skipping:", String(data).slice(0, 120));
            return;
        }
        if (!scheme || typeof scheme !== "object")
            return;

        if (!isPreview) {
            root.scheme = scheme.name;
            flavour = scheme.flavour;
            currentLight = scheme.mode === "light";
        } else {
            previewLight = scheme.mode === "light";
        }

        for (const [name, colour] of Object.entries(scheme.colours)) {
            const propName = name.startsWith("term") ? name : `m3${name}`;
            if (colours.hasOwnProperty(propName))
                colours[propName] = `#${colour}`;
        }
    }

    function setMode(mode: string): void {
        Quickshell.execDetached(["caelestia", "scheme", "set", "--notify", "-m", mode]);
    }

    function reloadHyprRules(): void {
        let rule, trEnabled;
        if (Hypr.usingLua) {
            rule = `eval hl.layer_rule({ match = { namespace = "caelestia-drawers" }, %1 = %2 })`;
            trEnabled = transparency.enabled;
        } else {
            rule = "keyword layerrule %1 %2, match:namespace caelestia-drawers";
            trEnabled = transparency.enabled ? 1 : 0;
        }
        Hypr.extras.batchMessage([rule.arg("blur").arg(trEnabled), rule.arg("ignore_alpha").arg(Math.max(0, transparency.base - 0.03))]);
    }

    function requestReloadHyprRules(): void {
        if (cooldownTimer.running) {
            root.cooldownPending = true;
        } else {
            root.reloadHyprRules();
            cooldownTimer.restart();
        }
    }

    Component.onCompleted: root.requestReloadHyprRules()

    Connections {
        function onConfigReloaded(): void {
            root.reloadHyprRules();
        }

        target: Hypr
    }

    FileView {
        path: `${Paths.state}/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.committedColoursJson = text();
            root.load(text(), false);
        }
    }

    ImageAnalyser {
        id: analyser

        source: Wallpapers.current
    }

    Timer {
        id: cooldownTimer

        interval: 30
        onTriggered: {
            if (root.cooldownPending) {
                root.cooldownPending = false;
                root.reloadHyprRules();
                restart();
            }
        }
    }

    Timer {
        id: cAnimCompleteTimer

        interval: Tokens.anim.durations.expressiveSlowEffects
        onTriggered: root.requestReloadHyprRules()
    }

    component Transparency: QtObject {
        readonly property bool enabled: LiquidGlass.enabled || Tokens.transparency.enabled
        readonly property real base: Math.max(0, Math.min(1, (LiquidGlass.enabled ? LiquidGlass.opacity : Tokens.transparency.base) - (root.light ? 0.1 : 0)))
        readonly property real layers: Math.max(0, Math.min(1, Tokens.transparency.layers))

        onEnabledChanged: {
            if (enabled)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
        }
        onBaseChanged: {
            if (root.lastBaseTransparency > base)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
            root.lastBaseTransparency = base;
        }
    }

    component M3TPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.layer(root.palette.m3primary_paletteKeyColor)
        readonly property color m3secondary_paletteKeyColor: root.layer(root.palette.m3secondary_paletteKeyColor)
        readonly property color m3tertiary_paletteKeyColor: root.layer(root.palette.m3tertiary_paletteKeyColor)
        readonly property color m3neutral_paletteKeyColor: root.layer(root.palette.m3neutral_paletteKeyColor)
        readonly property color m3neutral_variant_paletteKeyColor: root.layer(root.palette.m3neutral_variant_paletteKeyColor)
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 0)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 0)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface)
        readonly property color m3outline: root.layer(root.palette.m3outline)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant)
        readonly property color m3shadow: root.layer(root.palette.m3shadow)
        readonly property color m3scrim: root.layer(root.palette.m3scrim)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint)
        readonly property color m3primary: root.layer(root.palette.m3primary)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary)
        readonly property color m3secondary: root.layer(root.palette.m3secondary)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer)
        readonly property color m3error: root.layer(root.palette.m3error)
        readonly property color m3onError: root.layer(root.palette.m3onError)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer)
        readonly property color m3success: root.layer(root.palette.m3success)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant)
    }

    component M3RainbowPalette: M3Palette {
        // Rainbow-animated palette: surfaces and accents cycle through the spectrum.
        // Text colors stay fixed light so they remain readable at any hue.
        
        readonly property color m3primary_paletteKeyColor: RainbowAnimator.primary
        readonly property color m3secondary_paletteKeyColor: RainbowAnimator.secondary
        readonly property color m3tertiary_paletteKeyColor: RainbowAnimator.tertiary
        readonly property color m3neutral_paletteKeyColor: RainbowAnimator.surface
        readonly property color m3neutral_variant_paletteKeyColor: RainbowAnimator.surfaceVariant
        
        // Surfaces and accents cycle with hue
        property color m3background: RainbowAnimator.surface
        property color m3surface: RainbowAnimator.surface
        property color m3surfaceDim: RainbowAnimator.surface
        property color m3surfaceBright: RainbowAnimator.surfaceContainerHighest
        property color m3surfaceContainerLowest: RainbowAnimator.surface
        property color m3surfaceContainerLow: RainbowAnimator.surfaceContainer
        property color m3surfaceContainer: RainbowAnimator.surfaceContainer
        property color m3surfaceContainerHigh: RainbowAnimator.surfaceContainerHigh
        property color m3surfaceContainerHighest: RainbowAnimator.surfaceContainerHighest
        property color m3surfaceVariant: RainbowAnimator.surfaceVariant
        property color m3outline: RainbowAnimator.outline
        property color m3outlineVariant: RainbowAnimator.outlineVariant
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        
        // Text on dark surfaces stays fixed white
        property color m3onBackground: "#f0eff0"
        property color m3onSurface: "#f0eff0"
        property color m3onSurfaceVariant: "#bfbcc1"
        property color m3inverseSurface: "#f0eff0"
        property color m3inverseOnSurface: "#363538"
        
        // Accent + on-accent text stays fixed
        property color m3surfaceTint: RainbowAnimator.primary
        property color m3primary: RainbowAnimator.primary
        property color m3onPrimary: "#100022"
        property color m3primaryContainer: Qt.tint(RainbowAnimator.primary, RainbowAnimator.surfaceContainer)
        property color m3onPrimaryContainer: "#f4efff"
        property color m3inversePrimary: Qt.lighter(RainbowAnimator.primary, 1.3)
        
        property color m3secondary: RainbowAnimator.secondary
        property color m3onSecondary: "#2a2133"
        property color m3secondaryContainer: Qt.tint(RainbowAnimator.secondary, RainbowAnimator.surfaceContainer)
        property color m3onSecondaryContainer: "#f4efff"
        
        property color m3tertiary: RainbowAnimator.tertiary
        property color m3onTertiary: "#2a2415"
        property color m3tertiaryContainer: Qt.tint(RainbowAnimator.tertiary, RainbowAnimator.surfaceContainer)
        property color m3onTertiaryContainer: "#fff0d9"
        
        property color m3error: RainbowAnimator.error
        property color m3onError: "#ffffff"
        property color m3errorContainer: Qt.tint(RainbowAnimator.error, RainbowAnimator.surfaceContainer)
        property color m3onErrorContainer: "#410002"
        
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        
        property color m3primaryFixed: Qt.lighter(RainbowAnimator.primary, 1.8)
        property color m3primaryFixedDim: RainbowAnimator.primary
        property color m3onPrimaryFixed: "#100022"
        property color m3onPrimaryFixedVariant: Qt.darker(RainbowAnimator.primary, 1.5)
        
        property color m3secondaryFixed: Qt.lighter(RainbowAnimator.secondary, 1.8)
        property color m3secondaryFixedDim: RainbowAnimator.secondary
        property color m3onSecondaryFixed: "#2a2133"
        property color m3onSecondaryFixedVariant: Qt.darker(RainbowAnimator.secondary, 1.5)
        
        property color m3tertiaryFixed: Qt.lighter(RainbowAnimator.tertiary, 1.8)
        property color m3tertiaryFixedDim: RainbowAnimator.tertiary
        property color m3onTertiaryFixed: "#2a2415"
        property color m3onTertiaryFixedVariant: Qt.darker(RainbowAnimator.tertiary, 1.5)
        
        // Terminal text stays fixed white on dark surface
        property color term0: "#353434"
        property color term1: RainbowAnimator.error
        property color term2: RainbowAnimator.primary
        property color term3: RainbowAnimator.secondary
        property color term4: RainbowAnimator.tertiary
        property color term5: RainbowAnimator.secondary
        property color term6: RainbowAnimator.primary
        property color term7: "#f0eff0"
        property color term8: "#bfbcc1"
        property color term9: RainbowAnimator.error
        property color term10: RainbowAnimator.primary
        property color term11: "#f0eff0"
        property color term12: RainbowAnimator.tertiary
        property color term13: RainbowAnimator.secondary
        property color term14: RainbowAnimator.primary
        property color term15: "#ffffff"
    }

    component M3Palette: QtObject {
        property color m3primary_paletteKeyColor: "#a8627b"
        property color m3secondary_paletteKeyColor: "#8e6f78"
        property color m3tertiary_paletteKeyColor: "#986e4c"
        property color m3neutral_paletteKeyColor: "#807477"
        property color m3neutral_variant_paletteKeyColor: "#837377"
        property color m3background: "#191114"
        property color m3onBackground: "#efdfe2"
        property color m3surface: "#191114"
        property color m3surfaceDim: "#191114"
        property color m3surfaceBright: "#403739"
        property color m3surfaceContainerLowest: "#130c0e"
        property color m3surfaceContainerLow: "#22191c"
        property color m3surfaceContainer: "#261d20"
        property color m3surfaceContainerHigh: "#31282a"
        property color m3surfaceContainerHighest: "#3c3235"
        property color m3onSurface: "#efdfe2"
        property color m3surfaceVariant: "#514347"
        property color m3onSurfaceVariant: "#d5c2c6"
        property color m3inverseSurface: "#efdfe2"
        property color m3inverseOnSurface: "#372e30"
        property color m3outline: "#9e8c91"
        property color m3outlineVariant: "#514347"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#ffb0ca"
        property color m3primary: "#ffb0ca"
        property color m3onPrimary: "#541d34"
        property color m3primaryContainer: "#6f334a"
        property color m3onPrimaryContainer: "#ffd9e3"
        property color m3inversePrimary: "#8b4a62"
        property color m3secondary: "#e2bdc7"
        property color m3onSecondary: "#422932"
        property color m3secondaryContainer: "#5a3f48"
        property color m3onSecondaryContainer: "#ffd9e3"
        property color m3tertiary: "#f0bc95"
        property color m3onTertiary: "#48290c"
        property color m3tertiaryContainer: "#b58763"
        property color m3onTertiaryContainer: "#000000"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color m3primaryFixed: "#ffd9e3"
        property color m3primaryFixedDim: "#ffb0ca"
        property color m3onPrimaryFixed: "#39071f"
        property color m3onPrimaryFixedVariant: "#6f334a"
        property color m3secondaryFixed: "#ffd9e3"
        property color m3secondaryFixedDim: "#e2bdc7"
        property color m3onSecondaryFixed: "#2b151d"
        property color m3onSecondaryFixedVariant: "#5a3f48"
        property color m3tertiaryFixed: "#ffdcc3"
        property color m3tertiaryFixedDim: "#f0bc95"
        property color m3onTertiaryFixed: "#2f1500"
        property color m3onTertiaryFixedVariant: "#623f21"
        property color term0: "#353434"
        property color term1: "#ff4c8a"
        property color term2: "#ffbbb7"
        property color term3: "#ffdedf"
        property color term4: "#b3a2d5"
        property color term5: "#e98fb0"
        property color term6: "#ffba93"
        property color term7: "#eed1d2"
        property color term8: "#b39e9e"
        property color term9: "#ff80a3"
        property color term10: "#ffd3d0"
        property color term11: "#fff1f0"
        property color term12: "#dcbc93"
        property color term13: "#f9a8c2"
        property color term14: "#ffd1c0"
        property color term15: "#ffffff"
    }
}
