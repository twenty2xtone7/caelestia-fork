import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components.controls
import qs.modules.nexus.common
import qs.services
import qs.utils

PageBase {
    id: root

    title: Tr.tr("Lyrics")

    readonly property var cfg: DynLyricsConfig

    function itemFor(items: var, value: var): var {
        for (const i of items) {
            if (i.value === value)
                return i;
        }
        return items[0];
    }

    readonly property list<MenuItem> anchorItems: [
        MenuItem {
            text: Tr.tr("Top centre");
            value: "top-center"
        },
        MenuItem {
            text: Tr.tr("Top left");
            value: "top-left"
        },
        MenuItem {
            text: Tr.tr("Top right");
            value: "top-right"
        }
    ]

    readonly property list<MenuItem> widthItems: [
        MenuItem {
            text: Tr.tr("Fixed");
            value: "fixed"
        },
        MenuItem {
            text: Tr.tr("Auto");
            value: "auto"
        },
        MenuItem {
            text: Tr.tr("Auto with limits");
            value: "autoLimits"
        }
    ]

    readonly property list<MenuItem> easingItems: [
        MenuItem {
            text: "standard";
            value: "standard"
        },
        MenuItem {
            text: "standardAccel";
            value: "standardAccel"
        },
        MenuItem {
            text: "standardDecel";
            value: "standardDecel"
        },
        MenuItem {
            text: "emphasized";
            value: "emphasized"
        },
        MenuItem {
            text: "emphasizedAccel";
            value: "emphasizedAccel"
        },
        MenuItem {
            text: "emphasizedDecel";
            value: "emphasizedDecel"
        },
        MenuItem {
            text: "expressiveFastSpatial";
            value: "expressiveFastSpatial"
        },
        MenuItem {
            text: "expressiveDefaultSpatial";
            value: "expressiveDefaultSpatial"
        },
        MenuItem {
            text: "expressiveSlowSpatial";
            value: "expressiveSlowSpatial"
        }
    ]

    readonly property list<MenuItem> typeItems: [
        MenuItem {
            text: Tr.tr("Slide");
            value: "slide"
        },
        MenuItem {
            text: Tr.tr("Fade");
            value: "fade"
        },
        MenuItem {
            text: Tr.tr("Slide + fade");
            value: "slideFade"
        }
    ]

    readonly property list<MenuItem> directionItems: [
        MenuItem {
            text: Tr.tr("Left");
            value: "left"
        },
        MenuItem {
            text: Tr.tr("Right");
            value: "right"
        },
        MenuItem {
            text: Tr.tr("Up");
            value: "up"
        },
        MenuItem {
            text: Tr.tr("Down");
            value: "down"
        }
    ]

    readonly property list<MenuItem> weightItems: [
        MenuItem {
            text: Tr.tr("Thin");
            value: 100
        },
        MenuItem {
            text: Tr.tr("Light");
            value: 300
        },
        MenuItem {
            text: Tr.tr("Regular");
            value: 400
        },
        MenuItem {
            text: Tr.tr("Medium");
            value: 500
        },
        MenuItem {
            text: Tr.tr("Semi-bold");
            value: 600
        },
        MenuItem {
            text: Tr.tr("Bold");
            value: 700
        },
        MenuItem {
            text: Tr.tr("Black");
            value: 900
        }
    ]

    readonly property list<MenuItem> alignmentItems: [
        MenuItem {
            text: Tr.tr("Left");
            value: "left"
        },
        MenuItem {
            text: Tr.tr("Centre");
            value: "center"
        },
        MenuItem {
            text: Tr.tr("Right");
            value: "right"
        }
    ]

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        PageIntro {
            text: Tr.tr("Dynamic island lyrics panel: size, animation, typography and behaviour.")
        }

        // ── Appearance ───────────────────────────────────────────────────────
        SectionHeader {
            first: true
            text: Tr.tr("Appearance")
        }

        SelectRow {
            first: true
            label: Tr.tr("Anchor position")
            subtext: Tr.tr("Panel stays attached to the top screen edge")
            menuItems: root.anchorItems
            active: root.itemFor(root.anchorItems, root.cfg.anchorPosition)
            onSelected: item => root.cfg.anchorPosition = item.value
        }

        StepperRow {
            label: Tr.tr("Horizontal offset")
            subtext: Tr.tr("Shift along the top edge, in pixels")
            value: root.cfg.horizontalOffset
            from: -500
            to: 500
            stepSize: 4
            onMoved: v => root.cfg.horizontalOffset = v
        }

        SelectRow {
            label: Tr.tr("Width mode")
            subtext: Tr.tr("How the panel width is chosen")
            menuItems: root.widthItems
            active: root.itemFor(root.widthItems, root.cfg.widthMode)
            onSelected: item => root.cfg.widthMode = item.value
        }

        ToggleRow {
            text: Tr.tr("Auto width")
            subtext: Tr.tr("Track the rendered width of the current lyric")
            checked: root.cfg.autoWidth
            onToggled: root.cfg.autoWidth = checked
        }

        StepperRow {
            label: Tr.tr("Fixed width")
            subtext: Tr.tr("Used when auto width is off or the mode is Fixed")
            value: root.cfg.fixedWidth
            from: 40
            to: 2000
            stepSize: 10
            enabled: !root.cfg.autoWidth || root.cfg.widthMode === "fixed"
            onMoved: v => root.cfg.fixedWidth = v
        }

        StepperRow {
            label: Tr.tr("Minimum width")
            subtext: Tr.tr("Lower bound for Auto with limits")
            value: root.cfg.minWidth
            from: 40
            to: 2000
            stepSize: 10
            enabled: root.cfg.autoWidth && root.cfg.widthMode === "autoLimits"
            onMoved: v => root.cfg.minWidth = Math.min(v, root.cfg.maxWidth)
        }

        StepperRow {
            label: Tr.tr("Maximum width")
            subtext: Tr.tr("Upper bound for Auto with limits")
            value: root.cfg.maxWidth
            from: 40
            to: 2000
            stepSize: 10
            enabled: root.cfg.autoWidth && root.cfg.widthMode === "autoLimits"
            onMoved: v => root.cfg.maxWidth = Math.max(v, root.cfg.minWidth)
        }

        StepperRow {
            label: Tr.tr("Expanded height")
            subtext: Tr.tr("Height of the fully revealed panel")
            value: root.cfg.expandedHeight
            from: 16
            to: 400
            stepSize: 2
            onMoved: v => root.cfg.expandedHeight = v
        }

        StepperRow {
            label: Tr.tr("Collapsed height")
            subtext: Tr.tr("Height the panel collapses to")
            value: root.cfg.collapsedHeight
            from: 0
            to: 400
            stepSize: 2
            onMoved: v => root.cfg.collapsedHeight = v
        }

        StepperRow {
            label: Tr.tr("Horizontal padding")
            subtext: Tr.tr("Space between text and panel edges")
            value: root.cfg.horizontalPadding
            from: 0
            to: 64
            stepSize: 2
            onMoved: v => root.cfg.horizontalPadding = v
        }

        StepperRow {
            label: Tr.tr("Bottom corner radius")
            subtext: Tr.tr("Top corners stay square and attached to the edge")
            value: root.cfg.cornerRadius
            from: 0
            to: 64
            stepSize: 2
            onMoved: v => root.cfg.cornerRadius = v
        }

        ToggleRow {
            text: Tr.tr("Animate resizing")
            subtext: Tr.tr("Smoothly animate width changes")
            checked: root.cfg.resizeAnimation
            onToggled: root.cfg.resizeAnimation = checked
        }

        StepperRow {
            label: Tr.tr("Resize duration")
            value: root.cfg.resizeDuration
            from: 0
            to: 2000
            stepSize: 10
            enabled: root.cfg.resizeAnimation
            onMoved: v => root.cfg.resizeDuration = v
        }

        SelectRow {
            last: true
            label: Tr.tr("Resize easing")
            menuItems: root.easingItems
            active: root.itemFor(root.easingItems, root.cfg.resizeEasing)
            enabled: root.cfg.resizeAnimation
            onSelected: item => root.cfg.resizeEasing = item.value
        }

        InfoRow {
            first: true
            icon: "layers"
            label: Tr.tr("Background opacity & blur")
            subtext: Tr.tr("Unsupported: the panel shares the shell surface so it can merge with the bar")
            value: Tr.tr("Not available")
        }

        InfoRow {
            last: true
            icon: "blur_on"
            label: Tr.tr("Background blur")
            subtext: Tr.tr("The panel is a shape surface, not a backdrop-blur surface")
            value: Tr.tr("Not available")
        }

        // ── Panel Animation ──────────────────────────────────────────────────
        SectionHeader {
            text: Tr.tr("Panel Animation")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Enable panel animation")
            subtext: Tr.tr("Reveal and hide the panel by animating its height from the top edge")
            checked: root.cfg.panelAnimationEnabled
            onToggled: root.cfg.panelAnimationEnabled = checked
        }

        StepperRow {
            label: Tr.tr("Expansion duration")
            subtext: Tr.tr("Milliseconds to reveal the panel")
            value: root.cfg.expansionDuration
            from: 0
            to: 2000
            stepSize: 10
            enabled: root.cfg.panelAnimationEnabled
            onMoved: v => root.cfg.expansionDuration = v
        }

        StepperRow {
            label: Tr.tr("Collapse duration")
            subtext: Tr.tr("Milliseconds to hide the panel")
            value: root.cfg.collapseDuration
            from: 0
            to: 2000
            stepSize: 10
            enabled: root.cfg.panelAnimationEnabled
            onMoved: v => root.cfg.collapseDuration = v
        }

        StepperRow {
            label: Tr.tr("Animation delay")
            subtext: Tr.tr("Milliseconds before the expansion starts")
            value: root.cfg.animationDelay
            from: 0
            to: 2000
            stepSize: 10
            enabled: root.cfg.panelAnimationEnabled
            onMoved: v => root.cfg.animationDelay = v
        }

        SelectRow {
            label: Tr.tr("Easing")
            menuItems: root.easingItems
            active: root.itemFor(root.easingItems, root.cfg.easing)
            enabled: root.cfg.panelAnimationEnabled
            onSelected: item => root.cfg.easing = item.value
        }

        ToggleRow {
            text: Tr.tr("Content fade")
            subtext: Tr.tr("Fade the content in while the panel expands")
            checked: root.cfg.contentFade
            onToggled: root.cfg.contentFade = checked
        }

        StepperRow {
            label: Tr.tr("Content reveal delay")
            subtext: Tr.tr("Milliseconds before the content appears")
            value: root.cfg.contentRevealDelay
            from: 0
            to: 2000
            stepSize: 10
            enabled: root.cfg.panelAnimationEnabled
            onMoved: v => root.cfg.contentRevealDelay = v
        }

        StepperRow {
            last: true
            label: Tr.tr("Content slide distance")
            subtext: Tr.tr("Pixels the content travels during reveal")
            value: root.cfg.contentSlideDistance
            from: 0
            to: 200
            stepSize: 1
            enabled: root.cfg.panelAnimationEnabled
            onMoved: v => root.cfg.contentSlideDistance = v
        }

        // ── Lyrics Animation ────────────────────────────────────────────────
        SectionHeader {
            text: Tr.tr("Lyrics Animation")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Enable lyrics animation")
            subtext: Tr.tr("Animate the line change when the active lyric moves")
            checked: root.cfg.lyricsAnimationEnabled
            onToggled: root.cfg.lyricsAnimationEnabled = checked
        }

        SelectRow {
            label: Tr.tr("Animation type")
            menuItems: root.typeItems
            active: root.itemFor(root.typeItems, root.cfg.animationType)
            enabled: root.cfg.lyricsAnimationEnabled
            onSelected: item => root.cfg.animationType = item.value
        }

        SelectRow {
            label: Tr.tr("Direction")
            subtext: Tr.tr("Where the outgoing line leaves towards")
            menuItems: root.directionItems
            active: root.itemFor(root.directionItems, root.cfg.direction)
            enabled: root.cfg.lyricsAnimationEnabled && root.cfg.animationType !== "fade"
            onSelected: item => root.cfg.direction = item.value
        }

        StepperRow {
            label: Tr.tr("Transition duration")
            subtext: Tr.tr("Milliseconds the visual transition takes")
            value: root.cfg.transitionDuration
            from: 0
            to: 2000
            stepSize: 10
            enabled: root.cfg.lyricsAnimationEnabled
            onMoved: v => root.cfg.transitionDuration = v
        }

        StepperRow {
            label: Tr.tr("Transition delay")
            subtext: Tr.tr("Milliseconds before the visual transition starts")
            value: root.cfg.transitionDelay
            from: 0
            to: 2000
            stepSize: 10
            enabled: root.cfg.lyricsAnimationEnabled
            onMoved: v => root.cfg.transitionDelay = v
        }

        StepperRow {
            label: Tr.tr("Slide distance")
            subtext: Tr.tr("0 uses the full panel width or height")
            value: root.cfg.slideDistance
            from: 0
            to: 2000
            stepSize: 5
            enabled: root.cfg.lyricsAnimationEnabled && root.cfg.animationType !== "fade"
            onMoved: v => root.cfg.slideDistance = v
        }

        SelectRow {
            label: Tr.tr("Easing")
            menuItems: root.easingItems
            active: root.itemFor(root.easingItems, root.cfg.lyricEasing)
            enabled: root.cfg.lyricsAnimationEnabled
            onSelected: item => root.cfg.lyricEasing = item.value
        }

        ToggleRow {
            text: Tr.tr("Animate first lyric")
            subtext: Tr.tr("Animate the first line in rather than showing it instantly")
            checked: root.cfg.animateFirstLyric
            enabled: root.cfg.lyricsAnimationEnabled
            onToggled: root.cfg.animateFirstLyric = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Reset animation on track change")
            subtext: Tr.tr("Clear in-flight transitions when the track changes")
            checked: root.cfg.resetAnimationOnTrackChange
            enabled: root.cfg.lyricsAnimationEnabled
            onToggled: root.cfg.resetAnimationOnTrackChange = checked
        }

        // ── Typography ──────────────────────────────────────────────────────
        SectionHeader {
            text: Tr.tr("Typography")
        }

        TextFieldRow {
            first: true
            label: Tr.tr("Font family")
            subtext: Tr.tr("Leave empty to use the theme body font")
            placeholderText: Tokens.font.body.family
            value: root.cfg.fontFamily
            errorText: Tr.tr("Unknown font family")
            validate: t => !t || Qt.fontFamilies().indexOf(t) !== -1
            onEditingFinished: t => {
                const name = t.trim();
                if (!name || Qt.fontFamilies().indexOf(name) !== -1)
                    root.cfg.fontFamily = name;
            }
        }

        StepperRow {
            label: Tr.tr("Font size")
            subtext: Tr.tr("0 uses the theme size")
            value: root.cfg.fontSize
            from: 0
            to: 48
            stepSize: 1
            onMoved: v => root.cfg.fontSize = v
        }

        SelectRow {
            label: Tr.tr("Font weight")
            menuItems: root.weightItems
            active: root.itemFor(root.weightItems, root.cfg.fontWeight)
            onSelected: item => root.cfg.fontWeight = item.value
        }

        TextFieldRow {
            label: Tr.tr("Text colour")
            subtext: Tr.tr("Hex colour like #ffd8e4, empty uses the theme colour")
            placeholderText: "#ffffff"
            value: root.cfg.textColor
            errorText: Tr.tr("Use a hex colour or leave empty")
            validate: t => !t || /^#[0-9a-fA-F]{6}$/.test(t)
            onEditingFinished: t => {
                const c = t.trim();
                if (!c || /^#[0-9a-fA-F]{6}$/.test(c))
                    root.cfg.textColor = c;
            }
        }

        SliderRow {
            icon: "opacity"
            label: Tr.tr("Text opacity")
            valueLabel: Strings.percentOne(value)
            value: root.cfg.textOpacity
            onMoved: v => root.cfg.textOpacity = v
        }

        SelectRow {
            label: Tr.tr("Text alignment")
            menuItems: root.alignmentItems
            active: root.itemFor(root.alignmentItems, root.cfg.textAlignment)
            onSelected: item => root.cfg.textAlignment = item.value
        }

        StepperRow {
            label: Tr.tr("Line spacing")
            subtext: Tr.tr("Extra line height, 0 uses the font default")
            value: root.cfg.lineSpacing
            from: 0
            to: 48
            stepSize: 1
            onMoved: v => root.cfg.lineSpacing = v
        }

        ToggleRow {
            text: Tr.tr("Text shadow")
            subtext: Tr.tr("Draw a soft shadow behind the text")
            checked: root.cfg.textShadow
            onToggled: root.cfg.textShadow = checked
        }

        ToggleRow {
            text: Tr.tr("Show artist")
            checked: root.cfg.showArtist
            onToggled: root.cfg.showArtist = checked
        }

        ToggleRow {
            text: Tr.tr("Show track title")
            checked: root.cfg.showTrackTitle
            onToggled: root.cfg.showTrackTitle = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Show album")
            checked: root.cfg.showAlbum
            onToggled: root.cfg.showAlbum = checked
        }

        // ── Lyrics Behavior ─────────────────────────────────────────────────
        SectionHeader {
            text: Tr.tr("Lyrics Behavior")
        }

        StepperRow {
            first: true
            label: Tr.tr("Lyric sync offset")
            subtext: Tr.tr("Milliseconds added to playback before picking the active line")
            value: root.cfg.syncOffset
            from: -5000
            to: 5000
            stepSize: 50
            onMoved: v => root.cfg.syncOffset = v
        }

        ToggleRow {
            text: Tr.tr("Show previous and next lyrics")
            subtext: Tr.tr("Dim lines above and below the current one")
            checked: root.cfg.showPreviousAndNext
            onToggled: root.cfg.showPreviousAndNext = checked
        }

        ToggleRow {
            text: Tr.tr("Hide panel when lyrics are unavailable")
            subtext: Tr.tr("Collapse the panel while the track has no lyrics")
            checked: root.cfg.hidePanelWhenLyricsUnavailable
            onToggled: root.cfg.hidePanelWhenLyricsUnavailable = checked
        }

        TextFieldRow {
            last: true
            label: Tr.tr("Fallback text")
            subtext: Tr.tr("Shown when the track has no lyrics, empty uses the default")
            placeholderText: Tr.tr("No lyrics available")
            maximumLength: 120
            value: root.cfg.fallbackText
            onEditingFinished: t => root.cfg.fallbackText = t.trim()
        }

        // ── Advanced ────────────────────────────────────────────────────────
        SectionHeader {
            text: Tr.tr("Advanced")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Debug mode")
            subtext: Tr.tr("Overlay diagnostic information on the panel")
            checked: root.cfg.debugMode
            onToggled: root.cfg.debugMode = checked
        }

        ToggleRow {
            text: Tr.tr("Show current lyric index")
            checked: root.cfg.showLyricIndex
            enabled: root.cfg.debugMode
            onToggled: root.cfg.showLyricIndex = checked
        }

        ToggleRow {
            text: Tr.tr("Show playback position")
            checked: root.cfg.showPlaybackPosition
            enabled: root.cfg.debugMode
            onToggled: root.cfg.showPlaybackPosition = checked
        }

        ToggleRow {
            text: Tr.tr("Show effective sync offset")
            checked: root.cfg.showEffectiveSyncOffset
            enabled: root.cfg.debugMode
            onToggled: root.cfg.showEffectiveSyncOffset = checked
        }

        ToggleRow {
            text: Tr.tr("Pause animations when hidden")
            subtext: Tr.tr("Stop the position poll while the panel is not showing")
            checked: root.cfg.pauseAnimationsWhenHidden
            onToggled: root.cfg.pauseAnimationsWhenHidden = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Reduce animations")
            subtext: Tr.tr("Skip reveals and lyric transitions")
            checked: root.cfg.reduceAnimations
            onToggled: root.cfg.reduceAnimations = checked
        }

        RowButton {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            first: true
            last: true
            icon: "restart_alt"
            text: Tr.tr("Reset settings to defaults")
            onClicked: root.cfg.resetSettings()
        }
    }
}