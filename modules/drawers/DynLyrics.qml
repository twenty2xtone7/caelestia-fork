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
    // Wall-clock timestamp of the last `position` sync. MPRIS does not push
    // position updates, so the value above trails live playback by up to one
    // poll interval; seeks extrapolate from this to stay accurate.
    property real positionAt: 0

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
            root.positionAt = Date.now();
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

    // ── Seek ruler ───────────────────────────────────────────────────────────
    // Left click swaps the lyric pill for a scrub ruler in place: the wheel
    // steps the position, dragging scrubs, and a plain click closes it again.
    // The ruler slides under a fixed centre needle (it does not draw a moving
    // progress line), so scrolling moves the scale rather than the playhead.
    // Right click still closes the panel, and the panel keeps its normal size.
    property bool seeking: false
    property real seekProgress: root.seeking ? 1 : 0
    // Frozen copy of the width taken when the ruler opens, so lyric changes
    // cannot resize the panel out from under the scrubber.
    property real seekWidth: 0
    property real pendingSeek: -1
    property real lastSeekAt: 0
    // True while the pointer is dragging the scale. Playback polling is muted
    // in that window: the player only receives throttled seeks, so its reported
    // position lags the drag and would yank the ruler backwards.
    property bool scrubbing: false

    // Ruler scale: one minor tick per second. The wheel step is configurable
    // (DynLyricsConfig.seekStep, 0.5s by default), so one notch slides the
    // scale by half a second — six pixels at this density.
    readonly property real pxPerSec: 12
    // Desired ruler position. The 60Hz tick below eases `rulerPos` toward this,
    // so both continuous playback and discrete wheel notches glide; during a
    // drag the pointer sets it directly for 1:1 tracking.
    property real rulerTarget: 0
    // Rendered ruler position. Eased toward `rulerTarget` at 60 fps.
    property real rulerPos: 0

    readonly property var media: Players.active
    readonly property real trackLength: root.media?.length ?? 0
    readonly property color rulerColour: Colours.palette.m3onSurface
    readonly property color playColour: Colours.palette.m3primary

    function seekTo(pos: real, immediate: bool): void {
        const p = root.media;
        if (!p || !p.canSeek)
            return;
        const len = p.length || 0;
        const clamped = Math.max(0, len > 0 ? Math.min(pos, len) : pos);
        // Keep millisecond resolution: repeated fractional steps (0.5s, 0.1s)
        // must not accumulate float drift.
        const target = Math.round(clamped * 1000) / 1000;
        root.position = target; // paint immediately instead of waiting for the poll
        root.positionAt = Date.now();
        root.rulerTarget = target;
        if (root.scrubbing)
            root.rulerPos = target; // snap ruler for drag

        if (immediate) {
            root.lastSeekAt = Date.now();
            root.pendingSeek = -1;
            p.position = target;
            return;
        }

        // Scrubbing fires on every pointer move; committing all of them over
        // D-Bus makes some players stutter. Throttle and flush on release.
        const now = Date.now();
        if (now - root.lastSeekAt < 80) {
            root.pendingSeek = target;
            return;
        }
        root.lastSeekAt = now;
        root.pendingSeek = -1;
        p.position = target;
    }

    function commitSeek(): void {
        const p = root.media;
        if (!p || !p.canSeek || root.pendingSeek < 0)
            return;
        p.position = root.pendingSeek;
        root.pendingSeek = -1;
    }

    // Best estimate of the live position: the last polled value plus the time
    // elapsed since that poll. Without the extrapolation a 0.5s step computed
    // from a stale position can land behind playback and look like a no-op.
    function seekBase(): real {
        if (!root.isPlaying || root.positionAt <= 0)
            return root.position;
        return root.position + Math.max(0, Date.now() - root.positionAt) / 1000;
    }

    function seekBy(delta: real): void {
        root.seekTo(root.seekBase() + delta, true);
    }

    function toggleSeek(): void {
        if (!root.active)
            return;
        if (!root.seeking) {
            root.offsetting = false;
            root.seekWidth = root.width;
        }
        root.seeking = !root.seeking;
    }

    onSeekingChanged: {
        if (!root.seeking) {
            root.scrubbing = false;
            return;
        }
        root.media?.positionChanged();
        root.position = root.media?.position ?? 0;
        root.positionAt = Date.now();
        root.rulerTarget = root.position;
        root.rulerPos = root.position;
    }

    onActiveChanged: {
        if (!root.active) {
            root.seeking = false;
            root.offsetting = false;
        }
    }

    Behavior on seekProgress {
        enabled: root.cfg.panelAnimationEnabled && !root.reduced

        NumberAnimation {
            duration: root.seeking ? root.cfg.expansionDuration : root.cfg.collapseDuration
            easing: root.curve(root.cfg.easing)
        }
    }

    // 60Hz driver. During playback the target is the extrapolated position and
    // `rulerPos` eases toward it, so the scale glides continuously and a wheel
    // notch lands soft instead of teleporting. While dragging the pointer owns
    // the value, so both snap for 1:1 tracking.
    Timer {
        running: root.seeking
        interval: 16
        repeat: true
        onTriggered: {
            if (root.scrubbing) {
                root.rulerTarget = root.position;
                root.rulerPos = root.position;
                return;
            }
            root.rulerTarget = root.seekBase();
            root.rulerPos += (root.rulerTarget - root.rulerPos) * 0.35;
        }
    }

    // When paused, snap the ruler to the exact position.
    onIsPlayingChanged: {
        if (!root.isPlaying && root.seeking)
            root.rulerPos = root.position;
    }

    // ── Offset ruler ─────────────────────────────────────────────────────────
    // Middle click opens the sync offset ruler.
    property bool offsetting: false
    property real offsetProgress: root.offsetting ? 1 : 0
    property real offsetWidth: 0

    function toggleOffset(): void {
        if (!root.active)
            return;
        if (!root.offsetting)
            root.offsetWidth = root.width;
        root.offsetting = !root.offsetting;
    }

    Behavior on offsetProgress {
        enabled: root.cfg.panelAnimationEnabled && !root.reduced

        NumberAnimation {
            duration: root.offsetting ? root.cfg.expansionDuration : root.cfg.collapseDuration
            easing: root.curve(root.cfg.easing)
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
    // y is bound by Panels.qml to follow the dashboard's top edge.
    width: root.seeking ? root.seekWidth : (root.offsetting ? root.offsetWidth : root.stableWidth)
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
        opacity: (root.cfg.contentFade ? root.contentProgress : (root.contentProgress > 0 ? 1 : 0)) * (1 - root.seekProgress) * (1 - root.offsetProgress)

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
            // ponytail: Only run shadow offscreen pass when lyrics are showing
            layer.enabled: root.shown && Boolean(root.cfg?.textShadow)
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
    }

    // Hover/press feedback for the whole pill. It sits on the root rather than
    // inside `pill`: the root is clipped to the animated height while `pill`
    // keeps the expanded height, which drew the highlight as a hard square
    // block across a rounded surface. Radii mirror the panel surface so the
    // highlight can never poke past the corners.
    StateLayer {
        anchors.fill: parent
        enabled: root.shown && !root.seeking && !root.offsetting
        opacity: root.contentProgress * (1 - root.seekProgress) * (1 - root.offsetProgress)

        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => {
            if (event.button === Qt.RightButton)
                root.active = false;
            else if (event.button === Qt.MiddleButton)
                root.toggleOffset();
            else
                root.toggleSeek();
        }

        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: DynLyricsConfig.cornerRadius
        bottomRightRadius: DynLyricsConfig.cornerRadius
    }

    // ── Seek ruler UI ────────────────────────────────────────────────────────
    Item {
        id: seekUI

        anchors.fill: parent
        visible: root.seekProgress > 0.001
        opacity: root.seekProgress

        MouseArea {
            id: scrubArea

            property real wheelAccum: 0

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: root.media?.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
            focus: root.seeking

            property real pressX: 0
            property real lastX: 0
            property bool moved: false

            onPressed: event => {
                if (event.button !== Qt.LeftButton)
                    return;
                pressX = event.x;
                lastX = event.x;
                moved = false;
            }
            // A few pixels of travel tell "scrub" apart from "close". Dragging
            // moves the scale with the pointer, so dragging left scrubs forward.
            onPositionChanged: event => {
                if (!pressed || !(event.buttons & Qt.LeftButton))
                    return;
                if (!moved && Math.abs(event.x - pressX) < 4)
                    return;
                moved = true;
                root.scrubbing = true;
                root.seekTo(root.seekBase() - (event.x - lastX) / root.pxPerSec, false);
                lastX = event.x;
            }
            onReleased: event => {
                if (event.button !== Qt.LeftButton)
                    return;
                root.scrubbing = false;
                if (!moved)
                    root.seeking = false;
                else
                    root.commitSeek();
            }
            // Step comes from DynLyricsConfig.seekStep (0.5s by default);
            // Shift switches to a fifth of it for fine nudging. Accumulate so
            // touchpads do not fire a step per pixel of travel.
            onWheel: wheel => {
                wheelAccum += wheel.angleDelta.y || wheel.pixelDelta.y;
                const base = Math.max(0.05, root.cfg.seekStep);
                const step = (wheel.modifiers & Qt.ShiftModifier) ? base / 5 : base;
                const notches = Math.trunc(wheelAccum / 120);
                if (notches !== 0) {
                    root.seekBy(-notches * step);
                    wheelAccum -= notches * 120;
                }
                wheel.accepted = true;
            }
            onClicked: event => {
                if (event.button === Qt.RightButton) {
                    root.seeking = false;
                    root.active = false;
                }
            }

            // Spacebar pauses while the ruler is open. The layer window takes
            // keyboard focus only while seeking (ContentWindow.qml), so this
            // handler is active exactly when the ruler is highlighted.
            Keys.onSpacePressed: {
                root.media?.togglePlaying();
                event.accepted = true;
            }
        }

        Item {
            id: ruler

            anchors.fill: parent
            anchors.leftMargin: root.cfg.horizontalPadding
            anchors.rightMargin: root.cfg.horizontalPadding
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            clip: true

            // A real time scale: one second per minor tick, ten seconds per
            // tall one. The scale is drawn at an offset derived from
            // `rulerPos`; the needle below never moves.
            Canvas {
                id: ticks

                anchors.fill: parent

                property real pos: root.rulerPos
                property color tickColour: root.rulerColour

                onPosChanged: requestPaint()
                onTickColourChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const spacing = root.pxPerSec;
                    const first = Math.floor(pos);
                    const phase = (pos - first) * spacing;
                    const c = tickColour;
                    ctx.lineWidth = 1;
                    // Sub-pixel x so 60 fps ticks do not step a whole pixel at a
                    // time; canvas antialiasing keeps the thin lines crisp.
                    for (let k = 0; k * spacing - phase <= width; ++k) {
                        const x = k * spacing - phase;
                        if (x < 0)
                            continue;
                        const major = (first + k) % 10 === 0;
                        ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, major ? 0.45 : 0.2);
                        const th = height * (major ? 0.9 : 0.45);
                        const y0 = (height - th) / 2;
                        ctx.beginPath();
                        ctx.moveTo(x, y0);
                        ctx.lineTo(x, y0 + th);
                        ctx.stroke();
                    }
                }
            }

            Rectangle {
                id: playhead

                anchors.horizontalCenter: parent.horizontalCenter
                width: 2
                height: parent.height
                radius: 1
                color: root.playColour
                layer.enabled: seekUI.visible
                layer.effect: MultiEffect {
                    autoPaddingEnabled: true
                    shadowEnabled: true
                    shadowColor: Qt.alpha(root.playColour, 0.8)
                    shadowBlur: 0.7
                }
            }
        }
    }

    // ── Offset ruler UI ──────────────────────────────────────────────────────
    // Middle click swaps the lyric pill for a millisecond scale: the wheel and
    // drag move the sync offset, a plain click closes it again. The centre
    // needle stays fixed and the scale slides under it, same as the seek ruler.
    Item {
        id: offsetUI

        anchors.fill: parent
        visible: root.offsetProgress > 0.001
        opacity: root.offsetProgress

        // 1px = 5ms. Snap grid is 25ms = 5px, so each snap step is exactly one
        // visible tick and dragging is 1:1 with the scale.
        readonly property real msPerPx: 5
        // Canvas draws this. Kept in lockstep with the snapped setting via a
        // Binding (so it can never drift), except during a drag where the drag
        // handler writes it directly. The needle and the tick under it then
        // always share exactly the same millisecond value.
        property real shownOffset: 0
        property bool dragging: false

        // Snap every value to the 25ms minor-tick grid, so the needle always
        // lands exactly on a drawn tick.
        function setOffset(ms: real): void {
            const snapped = Math.round(ms / 25) * 25;
            root.cfg.syncOffset = Math.max(-5000, Math.min(5000, snapped));
        }

        Binding {
            target: offsetUI
            property: "shownOffset"
            value: root.cfg.syncOffset
            when: !offsetUI.dragging
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor

            property real pressX: 0
            property real lastX: 0
            property bool moved: false

            onPressed: event => {
                if (event.button !== Qt.LeftButton)
                    return;
                pressX = event.x;
                lastX = event.x;
                moved = false;
            }
            // Dragging left raises the offset, matching the seek ruler where
            // dragging left moves the scale forward.
            onPositionChanged: event => {
                if (!pressed || !(event.buttons & Qt.LeftButton))
                    return;
                if (!moved && Math.abs(event.x - pressX) < 4)
                    return;
                moved = true;
                offsetUI.dragging = true;
                offsetUI.setOffset(root.cfg.syncOffset - (event.x - lastX) * offsetUI.msPerPx);
                offsetUI.shownOffset = root.cfg.syncOffset;
                lastX = event.x;
            }
            onReleased: event => {
                if (event.button !== Qt.LeftButton)
                    return;
                offsetUI.dragging = false;
                if (!moved)
                    root.offsetting = false;
            }
            // Touchpads report continuous pixel travel; mice report 120 per notch.
            // At msPerPx: 10, one notch ÷ 24 = 5px = 50ms. Shift ÷ 120 = 1px = 10ms.
            onWheel: wheel => {
                const px = wheel.pixelDelta.y || wheel.angleDelta.y / (wheel.modifiers & Qt.ShiftModifier ? 120 : 24);
                if (px !== 0)
                    offsetUI.setOffset(root.cfg.syncOffset - px * offsetUI.msPerPx);
                wheel.accepted = true;
            }
            onClicked: event => {
                if (event.button === Qt.RightButton) {
                    root.offsetting = false;
                    root.active = false;
                } else if (event.button === Qt.MiddleButton || event.button === Qt.LeftButton) {
                    root.offsetting = false;
                }
            }
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: root.cfg.horizontalPadding
            anchors.rightMargin: root.cfg.horizontalPadding
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            clip: true

            // One tick per 10ms (1px), medium every 100ms, labelled every 500ms.
            Canvas {
                anchors.fill: parent

                property real offset: offsetUI.shownOffset
                property color tickColour: root.rulerColour

                onOffsetChanged: requestPaint()
                onTickColourChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const pxPerMs = 1 / offsetUI.msPerPx;
                    const centre = width / 2;
                    const c = tickColour;
                    ctx.lineWidth = 1;
                    ctx.font = "9px sans-serif";
                    ctx.textAlign = "center";

                    // Center is `offset`. Minor tick every 25ms (5px), medium every 100ms,
                    // tall + labelled every 500ms.
                    const tickStep = 25; // ms
                    const leftMs = offset - centre * offsetUI.msPerPx;
                    const rightMs = offset + centre * offsetUI.msPerPx;
                    const firstTick = Math.floor(leftMs / tickStep) * tickStep;

                    for (let ms = firstTick; ms <= rightMs; ms += tickStep) {
                        const x = centre + (ms - offset) * pxPerMs;
                        const isLabel = ms % 500 === 0;
                        const isMedium = ms % 100 === 0;
                        ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, isLabel ? 0.6 : (isMedium ? 0.35 : 0.16));
                        const th = height * (isLabel ? 0.9 : (isMedium ? 0.55 : 0.3));
                        const y0 = (height - th) / 2;
                        ctx.beginPath();
                        ctx.moveTo(x, y0);
                        ctx.lineTo(x, y0 + th);
                        ctx.stroke();
                        if (isLabel) {
                            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.75);
                            ctx.fillText(`${ms}ms`, x, height - 1);
                        }
                    }
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 2
                height: parent.height
                radius: 1
                color: root.playColour
            }
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
            // While dragging, the pointer owns the position; the player's
            // reported value trails the throttled seeks and would jerk the ruler.
            if (root.scrubbing)
                return;
            Players.active?.positionChanged();
            root.position = Players.active?.position ?? 0;
            root.positionAt = Date.now();
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
