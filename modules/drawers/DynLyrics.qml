pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.services

// Dyn-Lyrics: Dynamic Island-style pill anchored to the top edge.
//
// Lyrics come entirely from Caelestia's Lyrics singleton (import
// Caelestia.Services), the same backend Dashboard/Media uses via
// modules/dashboard/media/LyricList.qml: Lyrics.lyrics, Lyrics.hasLyrics,
// Lyrics.loading and Lyrics.indexForTime(). Track feeding is owned by
// services/Players.qml so nothing here re-requests the same track.
//
// Every knob below comes from services/DynLyricsConfig.qml (persisted to
// ~/.local/state/caelestia/dyn-lyrics.json) and the Nexus Dyn Lyrics pages.
Item {
    id: root
    objectName: "dynLyrics"

    required property ShellScreen screen
    property bool active: false

    readonly property var cfg: DynLyricsConfig
    readonly property bool reduced: root.cfg.reduceAnimations

    // Resolve a DynLyricsConfig easing name against the theme curves.
    function curve(name: string): var {
        switch (name) {
        case "standard":
            return Tokens.anim.standard;
        case "standardAccel":
            return Tokens.anim.standardAccel;
        case "standardDecel":
            return Tokens.anim.standardDecel;
        case "emphasized":
            return Tokens.anim.emphasized;
        case "emphasizedAccel":
            return Tokens.anim.emphasizedAccel;
        case "emphasizedDecel":
            return Tokens.anim.emphasizedDecel;
        case "expressiveFastSpatial":
            return Tokens.anim.expressiveFastSpatial;
        case "expressiveSlowSpatial":
            return Tokens.anim.expressiveSlowSpatial;
        }
        return Tokens.anim.expressiveDefaultSpatial;
    }

    // ── Lyrics source ────────────────────────────────────────────────────────
    readonly property bool isPlaying: Players.active?.isPlaying ?? false
    property real position: 0

    readonly property string trackArtist: Players.active?.trackArtist ?? ""
    readonly property string trackTitle: Players.active?.trackTitle ?? ""
    readonly property string trackAlbum: Players.active?.trackAlbum ?? ""

    readonly property bool lyricsUnavailable: !Lyrics.hasLyrics && !Lyrics.loading
    readonly property bool shown: root.active && !(root.cfg.hidePanelWhenLyricsUnavailable && root.lyricsUnavailable)

    // The sync offset only shifts which line counts as active. The backend's
    // own timestamps are never modified.
    readonly property real effectivePosition: root.position + root.cfg.syncOffset / 1000

    // Read the effective position into a local first: with the call inline
    // inside the ternary QML does not register it as a binding dependency, so
    // the index freezes at -1 and lyrics never appear.
    readonly property int currentIndex: {
        const pos = root.effectivePosition;
        const n = Lyrics.lyrics.length;
        return Lyrics.hasLyrics && n > 0 ? Lyrics.indexForTime(pos) : -1;
    }

    function lineAt(i: int): string {
        const n = Lyrics.lyrics.length;
        return i >= 0 && i < n ? (Lyrics.lyrics[i] ?? "").trim() : "";
    }

    readonly property string currentLine: root.lineAt(root.currentIndex)
    readonly property string prevLine: root.lineAt(root.currentIndex - 1)
    readonly property string nextLine: root.lineAt(root.currentIndex + 1)

    // Hold the last real line through instrumental gaps instead of blanking out.
    property string lastLine: ""
    onCurrentLineChanged: if (currentLine)
        lastLine = currentLine

    Connections {
        target: Lyrics

        function onTrackChanged(): void {
            root.lastLine = "";
            if (root.cfg.resetAnimationOnTrackChange)
                lyricView.reset();
        }
    }

    readonly property string displayLine: {
        if (root.currentLine)
            return root.currentLine;
        if (Lyrics.loading)
            return Tr.tr("Loading lyrics...");
        if (Lyrics.hasLyrics)
            return root.lastLine || "♪";
        return root.cfg.fallbackText || Tr.tr("No lyrics available");
    }

    readonly property string metaLine: {
        const parts = [];
        if (root.cfg.showArtist && root.trackArtist)
            parts.push(root.trackArtist);
        if (root.cfg.showTrackTitle && root.trackTitle)
            parts.push(root.trackTitle);
        if (root.cfg.showAlbum && root.trackAlbum)
            parts.push(root.trackAlbum);
        return parts.join(" · ");
    }

    // ── Typography ───────────────────────────────────────────────────────────
    function buildFont(scale: real): var {
        let b = Tokens.font.body.builders.small;
        if (root.cfg.fontFamily)
            b = b.family(root.cfg.fontFamily);
        if (root.cfg.fontSize > 0)
            b = b.size(root.cfg.fontSize);
        b = b.weight(root.cfg.fontWeight);
        return scale === 1 ? b.build() : b.scale(scale).build();
    }

    readonly property var lyricFont: root.buildFont(1)
    readonly property var metaFont: root.buildFont(0.78)

    readonly property color lyricColour: root.cfg.textColor ? root.cfg.textColor : Colours.palette.m3onSurface
    readonly property int hAlign: root.cfg.textAlignment === "left" ? Text.AlignLeft : root.cfg.textAlignment === "right" ? Text.AlignRight : Text.AlignHCenter

    TextMetrics {
        id: lyricMetrics

        font: root.lyricFont
        text: root.displayLine
    }

    TextMetrics {
        id: metaMetrics

        font: root.metaFont
        text: root.metaLine
    }

    TextMetrics {
        id: prevMetrics

        font: root.metaFont
        text: root.cfg.showPreviousAndNext ? root.prevLine : ""
    }

    TextMetrics {
        id: nextMetrics

        font: root.metaFont
        text: root.cfg.showPreviousAndNext ? root.nextLine : ""
    }

    // ── Dynamic width ────────────────────────────────────────────────────────
    // Icon + its margins, the text block, plus the configured padding.
    readonly property real measuredWidth: Math.ceil(icon.implicitWidth + Tokens.padding.medium + Tokens.spacing.small + Math.max(lyricMetrics.advanceWidth, Math.max(metaMetrics.advanceWidth, Math.max(prevMetrics.advanceWidth, nextMetrics.advanceWidth))) + root.cfg.horizontalPadding * 2)

    readonly property real targetWidth: {
        const avail = Math.max(80, root.screen.width - Tokens.padding.large * 2);
        let w;
        if (!root.cfg.autoWidth || root.cfg.widthMode === "fixed")
            w = root.cfg.fixedWidth;
        else if (root.cfg.widthMode === "auto")
            w = root.measuredWidth;
        else
            w = Math.min(root.cfg.maxWidth, Math.max(root.cfg.minWidth, root.measuredWidth));
        return Math.min(avail, Math.max(40, w));
    }

    // Near-identical consecutive widths must not restart the resize animation.
    readonly property real widthDeadband: 6
    property real stableWidth: 0

    // Width *settings* bypass the deadband so a change applies immediately.
    readonly property string widthKey: `${root.cfg.autoWidth}|${root.cfg.widthMode}|${root.cfg.fixedWidth}|${root.cfg.minWidth}|${root.cfg.maxWidth}|${root.cfg.horizontalPadding}|${root.cfg.fontFamily}|${root.cfg.fontSize}|${root.cfg.fontWeight}`
    onWidthKeyChanged: root.stableWidth = root.targetWidth
    onTargetWidthChanged: if (root.stableWidth === 0 || Math.abs(root.targetWidth - root.stableWidth) > root.widthDeadband)
        root.stableWidth = root.targetWidth

    // ── Panel / content reveal ───────────────────────────────────────────────
    // Top edge stays pinned at y = 0; the height animates from the collapsed
    // height to the expanded height and the root clip reveals it downwards.
    // Plain properties, not bound to `shown`: a binding would snap the value to
    // its target before reveal() runs, leaving the animation with from == to.
    property real offsetScale: 1
    property real contentProgress: 0

    readonly property real collapsedHeight: Math.min(root.cfg.collapsedHeight, root.cfg.expandedHeight)

    function reveal(): void {
        const to = root.shown ? 0 : 1;
        panelAnim.stop();
        contentAnim.stop();

        if (!root.cfg.panelAnimationEnabled || root.reduced) {
            root.offsetScale = to;
            root.contentProgress = root.shown ? 1 : 0;
            return;
        }

        const dur = root.shown ? root.cfg.expansionDuration : root.cfg.collapseDuration;
        expandAnim.from = root.offsetScale;
        expandAnim.to = to;
        expandAnim.duration = dur;
        expandAnim.easing = root.curve(root.cfg.easing);
        panelDelay.duration = root.cfg.animationDelay;
        contentAnimStep.from = root.contentProgress;
        contentAnimStep.to = root.shown ? 1 : 0;
        contentAnimStep.duration = dur;
        contentAnimStep.easing = root.curve(root.cfg.easing);
        contentDelay.duration = root.cfg.contentRevealDelay;
        panelAnim.restart();
        contentAnim.restart();
    }

    onShownChanged: {
        root.reveal();
        if (root.shown) {
            // Paused polling leaves a stale line behind; refresh on open.
            Players.active?.positionChanged();
            root.position = Players.active?.position ?? 0;
        }
    }

    SequentialAnimation {
        id: panelAnim

        PauseAnimation {
            id: panelDelay
        }
        NumberAnimation {
            id: expandAnim

            target: root
            property: "offsetScale"
        }
    }

    SequentialAnimation {
        id: contentAnim

        PauseAnimation {
            id: contentDelay
        }
        NumberAnimation {
            id: contentAnimStep

            target: root
            property: "contentProgress"
        }
    }

    // ── Geometry ─────────────────────────────────────────────────────────────
    function alignmentOffset(): real {
        const free = root.parent ? Math.max(0, root.parent.width - root.width) : 0;
        if (root.cfg.anchorPosition === "top-left")
            return -free / 2;
        if (root.cfg.anchorPosition === "top-right")
            return free / 2;
        return 0;
    }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: root.alignmentOffset() + root.cfg.horizontalOffset
    // Fixed top edge: the panel always grows downwards from y = 0.
    y: 0
    width: root.stableWidth
    height: root.collapsedHeight + (root.cfg.expandedHeight - root.collapsedHeight) * (1 - offsetScale)
    visible: height > 0.5
    clip: true
    z: 1000

    Behavior on width {
        enabled: root.cfg.resizeAnimation && !root.reduced

        NumberAnimation {
            duration: root.cfg.resizeDuration
            easing: root.curve(root.cfg.resizeEasing)
        }
    }

    // ── Content ──────────────────────────────────────────────────────────────
    Item {
        id: pill

        width: root.width
        height: root.cfg.expandedHeight
        // Content slides down by its own distance while the panel height is
        // driven by the reveal animation above (independent of it).
        y: -root.cfg.contentSlideDistance * (1 - root.contentProgress)
        opacity: root.cfg.contentFade ? root.contentProgress : (root.contentProgress > 0 ? 1 : 0)

        MaterialIcon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.medium

            text: "music_note"
            color: Colours.palette.m3primary
        }

        Item {
            id: textArea

            anchors.left: icon.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: Tokens.spacing.small
            anchors.rightMargin: root.cfg.horizontalPadding

            clip: true
            layer.enabled: root.cfg.textShadow
            layer.effect: MultiEffect {
                autoPaddingEnabled: true
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.7)
                shadowBlur: 0.6
                shadowVerticalOffset: 1
            }

            StyledText {
                id: metaText

                anchors.top: parent.top
                width: parent.width
                horizontalAlignment: root.hAlign
                elide: Text.ElideRight
                visible: text !== ""
                text: root.metaLine
                color: root.lyricColour
                opacity: 0.6 * root.cfg.textOpacity
                font: root.metaFont
                lineHeight: root.cfg.lineSpacing
            }

            StyledText {
                id: prevText

                anchors.bottom: lyricView.top
                width: parent.width
                horizontalAlignment: root.hAlign
                elide: Text.ElideRight
                visible: root.cfg.showPreviousAndNext
                text: root.prevLine
                color: root.lyricColour
                opacity: 0.4 * root.cfg.textOpacity
                font: root.metaFont
                lineHeight: root.cfg.lineSpacing
            }

            StyledText {
                id: nextText

                anchors.top: lyricView.bottom
                width: parent.width
                horizontalAlignment: root.hAlign
                elide: Text.ElideRight
                visible: root.cfg.showPreviousAndNext
                text: root.nextLine
                color: root.lyricColour
                opacity: 0.4 * root.cfg.textOpacity
                font: root.metaFont
                lineHeight: root.cfg.lineSpacing
            }

            // Per-line transition: two full-width slots. The visible one is
            // stationary; on an index change one leaves while the other enters,
            // then both settle until the next change. Never loops, never
            // marquees, never repeats a line.
            Item {
                id: lyricView

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(lyricMetrics.height, parent.height * 0.5)
                clip: true

                property bool usingA: true
                property bool primed: false
                property string shownLine: ""

                readonly property string axis: (root.cfg.direction === "left" || root.cfg.direction === "right") ? "x" : "y"
                // "left"/"up": the old line leaves towards the negative side and
                // the new one enters from the positive side.
                readonly property real sign: (root.cfg.direction === "left" || root.cfg.direction === "up") ? 1 : -1
                readonly property real distance: root.cfg.slideDistance > 0 ? root.cfg.slideDistance : (lyricView.axis === "x" ? lyricView.width : lyricView.height)

                function place(slot: Item, d: real): void {
                    if (lyricView.axis === "x") {
                        slot.x = d;
                        slot.y = 0;
                    } else {
                        slot.y = d;
                        slot.x = 0;
                    }
                }

                function reset(): void {
                    slideAnim.stop();
                    primed = false;
                    shownLine = "";
                    slotA.text = "";
                    slotB.text = "";
                    usingA = true;
                    place(slotA, 0);
                    place(slotB, 0);
                    slotA.opacity = 1;
                    slotB.opacity = 0;
                }

                function transitionAllowed(): bool {
                    return root.cfg.lyricsAnimationEnabled && !root.reduced && !(root.cfg.pauseAnimationsWhenHidden && !root.shown);
                }

                function setLine(line: string): void {
                    if (line === shownLine)
                        return;
                    shownLine = line;

                    const animate = transitionAllowed();

                    if (!primed) {
                        primed = true;
                        if (!animate || !root.cfg.animateFirstLyric) {
                            slideAnim.stop();
                            slotA.text = line;
                            slotB.text = "";
                            usingA = true;
                            place(slotA, 0);
                            place(slotB, 0);
                            slotA.opacity = 1;
                            slotB.opacity = 0;
                            return;
                        }
                    }

                    if (!animate) {
                        slideAnim.stop();
                        const cur = usingA ? slotA : slotB;
                        const other = usingA ? slotB : slotA;
                        cur.text = line;
                        place(cur, 0);
                        cur.opacity = 1;
                        other.text = "";
                        other.opacity = 0;
                        return;
                    }

                    // A newer change replaces an in-flight one instead of stacking.
                    if (slideAnim.running)
                        slideAnim.complete();

                    const out = usingA ? slotA : slotB;
                    const inc = usingA ? slotB : slotA;
                    const type = root.cfg.animationType;
                    const sliding = type !== "fade";
                    const fading = type !== "slide";
                    const d = lyricView.distance;

                    inc.text = line;
                    place(out, 0);
                    place(inc, sliding ? lyricView.sign * d : 0);
                    out.opacity = 1;
                    inc.opacity = fading ? 0 : 1;

                    outSlide.property = lyricView.axis;
                    inSlide.property = lyricView.axis;

                    outSlide.target = out;
                    outSlide.from = 0;
                    outSlide.to = sliding ? -lyricView.sign * d : 0;
                    outFade.target = out;
                    outFade.from = out.opacity;
                    outFade.to = fading ? 0 : 1;

                    inSlide.target = inc;
                    inSlide.from = sliding ? lyricView.sign * d : 0;
                    inSlide.to = 0;
                    inFade.target = inc;
                    inFade.from = fading ? 0 : 1;
                    inFade.to = 1;

                    usingA = !usingA;
                    transDelay.duration = root.cfg.transitionDelay;
                    slideAnim.restart();
                }

                SequentialAnimation {
                    id: slideAnim

                    PauseAnimation {
                        id: transDelay
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            id: outSlide

                            property: "x"
                            duration: root.reduced ? 0 : root.cfg.transitionDuration
                            easing: root.curve(root.cfg.lyricEasing)
                        }
                        NumberAnimation {
                            id: outFade

                            property: "opacity"
                            duration: root.reduced ? 0 : root.cfg.transitionDuration
                            easing: root.curve(root.cfg.lyricEasing)
                        }
                        NumberAnimation {
                            id: inSlide

                            property: "x"
                            duration: root.reduced ? 0 : root.cfg.transitionDuration
                            easing: root.curve(root.cfg.lyricEasing)
                        }
                        NumberAnimation {
                            id: inFade

                            property: "opacity"
                            duration: root.reduced ? 0 : root.cfg.transitionDuration
                            easing: root.curve(root.cfg.lyricEasing)
                        }
                    }
                }

                Item {
                    id: slotA

                    property string text: ""

                    width: lyricView.width
                    height: lyricView.height

                    StyledText {
                        width: parent.width
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: root.hAlign
                        elide: Text.ElideRight
                        font: root.lyricFont
                        lineHeight: root.cfg.lineSpacing
                        color: root.lyricColour
                        opacity: root.cfg.textOpacity
                        text: slotA.text
                    }
                }

                Item {
                    id: slotB

                    property string text: ""

                    width: lyricView.width
                    height: lyricView.height
                    opacity: 0

                    StyledText {
                        width: parent.width
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: root.hAlign
                        elide: Text.ElideRight
                        font: root.lyricFont
                        lineHeight: root.cfg.lineSpacing
                        color: root.lyricColour
                        opacity: root.cfg.textOpacity
                        text: slotB.text
                    }
                }
            }

            // Debug overlay: only rendered when Debug Mode is on.
            StyledText {
                id: debugText

                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: root.cfg.debugMode
                font: Tokens.font.label.builders.small.build()
                color: Colours.palette.m3primary
                opacity: 0.8

                text: {
                    if (!root.cfg.debugMode)
                        return "";
                    const parts = [];
                    if (root.cfg.showLyricIndex)
                        parts.push(`#${root.currentIndex}`);
                    if (root.cfg.showPlaybackPosition)
                        parts.push(`${root.position.toFixed(2)}s`);
                    if (root.cfg.showEffectiveSyncOffset)
                        parts.push(`off ${root.cfg.syncOffset}ms`);
                    return parts.join(" ");
                }
            }
        }

        StateLayer {
            anchors.fill: parent
            showHoverBackground: false

            acceptedButtons: Qt.RightButton
            onClicked: root.active = false
        }
    }

    // Track sync owned by services/Players.qml; this only polls position.

    // Players.position has no notify signal, so poll it like the dashboard does.
    Timer {
        running: root.isPlaying && (root.active || !root.cfg.pauseAnimationsWhenHidden)
        interval: GlobalConfig.dashboard.mediaUpdateInterval
        triggeredOnStart: true
        repeat: true
        onTriggered: {
            Players.active?.positionChanged();
            root.position = Players.active?.position ?? 0;
        }
    }

    onDisplayLineChanged: lyricView.setLine(root.displayLine)

    Component.onCompleted: {
        root.stableWidth = root.targetWidth;
        root.offsetScale = root.shown ? 0 : 1;
        root.contentProgress = root.shown ? 1 : 0;
        lyricView.place(slotA, 0);
        lyricView.place(slotB, 0);
        lyricView.setLine(root.displayLine);
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "dynLyrics"
        component: root
    }
}
