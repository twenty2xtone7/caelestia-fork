pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.services
import qs.modules.launcher.items

// Music mini-app. The launcher morphs into this view when the
// `/music` action is selected; Escape morphs back to the action list.
// Search is debounced and non-blocking; playback is owned by the
// persistent MusicService player so it survives launcher visibility.
Item {
    id: root

    required property var screenState
    required property SearchBar search

    signal closeRequested

    // One-shot: apply the saved selection once results are (re)populated.
    property bool _restoreIndex: false

    function backToActions(): void {
        Actions.closeMiniApp();
        search.text = GlobalConfig.launcher.actionPrefix;
        search.forceActiveFocus();
        closeRequested();
    }

    function fmtMs(ms: real): string {
        if (!ms || ms <= 0)
            return "0:00";
        const total = Math.floor(ms / 1000);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    function playSelected(): void {
        const item = resultsView.currentItem;
        if (item && item.modelData)
            MusicService.resolveAndPlay(item.modelData);
        else if (MusicService.results.length > 0)
            MusicService.resolveAndPlay(MusicService.results[resultsView.currentIndex] ?? MusicService.results[0]);
    }

    function downloadSelected(): void {
        const item = resultsView.currentItem;
        if (item && item.modelData)
            MusicService.download(item.modelData);
        else if (MusicService.results.length > 0)
            MusicService.download(MusicService.results[resultsView.currentIndex] ?? MusicService.results[0]);
    }

    function enqueueSelected(): void {
        const item = resultsView.currentItem;
        if (item && item.modelData)
            MusicService.enqueue(item.modelData);
        else if (MusicService.results.length > 0)
            MusicService.enqueue(MusicService.results[resultsView.currentIndex] ?? MusicService.results[0]);
    }

    implicitWidth: Tokens.sizes.launcher.itemWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right

        spacing: Tokens.spacing.medium

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconButton {
                icon: "close"
                type: IconButton.Text
                onClicked: root.backToActions()
            }

            StyledText {
                text: Tr.tr("Music")
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                Layout.fillWidth: true
            }

            StyledText {
                visible: MusicService.searching || MusicService.resolving || MusicService.downloading
                text: {
                    if (MusicService.downloading && MusicService.downloadProgress)
                        return Tr.tr("Downloading %1%").arg(MusicService.downloadProgress);
                    if (MusicService.downloading)
                        return Tr.tr("Downloading…");
                    if (MusicService.resolving)
                        return Tr.tr("Resolving…");
                    return Tr.tr("Searching…");
                }
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        // Search input
        StyledTextField {
            id: inputField

            Layout.fillWidth: true
            placeholderText: Tr.tr("Search music… (Enter play, Q queue, D download)")
            onAccepted: {
                if (!text.trim())
                    return;
                MusicService.search(text);
                if (MusicService.results.length > 0)
                    resultsView.forceActiveFocus();
            }
            onTextEdited: {
                MusicService.savedQuery = text;
                MusicService.debouncedSearch(text);
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.backToActions();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    if (resultsView.count > 0) {
                        resultsView.forceActiveFocus();
                        resultsView.currentIndex = 0;
                    }
                    event.accepted = true;
                }
            }
        }

        // Error / status line
        StyledText {
            visible: !!MusicService.error
            Layout.fillWidth: true
            text: MusicService.error
            font: Tokens.font.body.small
            color: Colours.palette.m3error
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        // Results
        StyledListView {
            id: resultsView

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(count, 6) * (Tokens.sizes.launcher.itemHeight + spacing) - spacing
            visible: count > 0

            spacing: Tokens.spacing.small
            orientation: Qt.Vertical
            model: MusicService.results
            delegate: MusicItem {
                list: resultsView
            }

            onCurrentIndexChanged: MusicService.savedIndex = currentIndex

            Connections {
                function onResultsChanged(): void {
                    if (root._restoreIndex && resultsView.count > 0) {
                        root._restoreIndex = false;
                        resultsView.currentIndex = Math.min(Math.max(MusicService.savedIndex, 0), resultsView.count - 1);
                        resultsView.positionViewAtIndex(resultsView.currentIndex, ListView.Contain);
                    }
                }

                target: MusicService
            }

            highlightFollowsCurrentItem: false
            highlight: StyledRect {
                radius: Tokens.rounding.large
                color: Colours.palette.m3onSurface
                opacity: 0.08

                y: resultsView.currentItem?.y ?? 0
                implicitWidth: resultsView.width
                implicitHeight: resultsView.currentItem?.implicitHeight ?? 0

                Behavior on y {
                    Anim {}
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.playSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_D && event.modifiers === Qt.NoModifier) {
                    root.downloadSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Q && event.modifiers === Qt.NoModifier) {
                    root.enqueueSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.backToActions();
                    event.accepted = true;
                }
            }
        }

        // Empty hint
        StyledText {
            visible: resultsView.count === 0 && !MusicService.searching && !MusicService.error
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: MusicService.library.length > 0 ? Tr.tr("Type to search, or pick from your library below") : Tr.tr("Type at least 2 characters to search")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        // Now playing
        StyledRect {
            visible: !!MusicService.currentTitle
            Layout.fillWidth: true
            implicitHeight: nowPlayingLayout.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: nowPlayingLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium

                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: MusicService.isPlaying ? "music_note" : "music_off"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: MusicService.currentArtist ? `${MusicService.currentArtist} — ${MusicService.currentTitle}` : MusicService.currentTitle
                        font: Tokens.font.body.medium
                        elide: Text.ElideRight
                    }

                    IconButton {
                        icon: MusicService.isPaused || !MusicService.isPlaying ? "play_arrow" : "pause"
                        type: IconButton.Text
                        onClicked: MusicService.togglePlay()
                    }

                    IconButton {
                        icon: "stop"
                        type: IconButton.Text
                        onClicked: MusicService.stopPlayback()
                    }

                    IconButton {
                        icon: "skip_next"
                        type: IconButton.Text
                        opacity: MusicService.queue.length > 0 ? 1 : 0.4
                        onClicked: MusicService.playNext()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    visible: MusicService.seekableLengthMs > 0

                    StyledText {
                        text: root.fmtMs(MusicService.playbackPosition)
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledSlider {
                        Layout.fillWidth: true
                        from: 0
                        to: Math.max(MusicService.seekableLengthMs, 1)
                        value: Math.min(MusicService.playbackPosition, to)
                        enabled: MusicService.seekableLengthMs > 0
                        interactionOnMove: false
                        // interaction() reports a normalised 0..1 position,
                        // not a value: scale it to milliseconds.
                        onInteraction: v => MusicService.seekTo(v * Math.max(MusicService.seekableLengthMs, 1))
                    }

                    StyledText {
                        text: root.fmtMs(MusicService.seekableLengthMs)
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    IconButton {
                        icon: "volume_up"
                        type: IconButton.Text
                        onClicked: MusicService.setVolume(MusicService.volume > 0 ? 0 : 0.8)
                    }

                    StyledSlider {
                        Layout.preferredWidth: 90
                        from: 0
                        to: 1
                        value: MusicService.volume
                        onInteraction: v => MusicService.setVolume(v)
                    }

                    // Output device selector (system-wide PipeWire sink)
                    IconButton {
                        id: deviceBtn
                        icon: "speaker"
                        type: IconButton.Text
                        opacity: Audio.sinks.length > 1 ? 1 : 0.4
                        onClicked: {
                            if (Audio.sinks.length < 2)
                                Toaster.toast(Tr.tr("Output device"), Tr.tr("Only one output device found"), "speaker");
                            else
                                Audio.cycleNextAudioOutput();
                        }
                    }

                    // Repeat button
                    IconButton {
                        icon: MusicService.repeat ? "repeat_on" : "repeat"
                        type: IconButton.Text
                        onClicked: MusicService.repeat = !MusicService.repeat
                    }
                }
            }
        }

        // Up next (play queue)
        ColumnLayout {
            visible: MusicService.queue.length > 0
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Up next (%1)").arg(MusicService.queue.length)
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                IconButton {
                    icon: "clear_all"
                    type: IconButton.Text
                    onClicked: MusicService.clearQueue()
                }
            }

            Repeater {
                model: MusicService.queue.slice(0, 8)

                delegate: Item {
                    id: queueRow

                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: Tokens.sizes.launcher.itemHeight * 0.7

                    StateLayer {
                        radius: Tokens.rounding.large
                        onClicked: MusicService.playQueueIndex(queueRow.index)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.small
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: `${queueRow.index + 1}.`
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: queueRow.modelData.artist ? `${queueRow.modelData.artist} — ${queueRow.modelData.title}` : queueRow.modelData.title
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        IconButton {
                            icon: "close"
                            type: IconButton.Text
                            onClicked: MusicService.removeFromQueue(queueRow.index)
                        }
                    }
                }
            }

            StyledText {
                visible: MusicService.queue.length > 8
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Tr.tr("+%1 more").arg(MusicService.queue.length - 8)
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        // Library
        ColumnLayout {
            visible: MusicService.library.length > 0
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: Tr.tr("Library (%1)").arg(MusicService.library.length)
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            Repeater {
                model: MusicService.library.slice(0, 5)

                delegate: Item {
                    id: libRow

                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: Tokens.sizes.launcher.itemHeight * 0.8

                    StateLayer {
                        radius: Tokens.rounding.large
                        onClicked: MusicService.playLocal(libRow.modelData.path, libRow.modelData.title, libRow.modelData.artist)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "audio_file"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: libRow.modelData.artist ? `${libRow.modelData.artist} — ${libRow.modelData.title}` : libRow.modelData.title
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        const initial = Actions.miniAppInitialText || "";
        const query = initial || MusicService.savedQuery;
        if (query) {
            inputField.text = query;
            MusicService.savedQuery = query;
            // Restore the saved selection once results are shown; only
            // re-search when nothing is in flight and the shown results
            // belong to a different query.
            root._restoreIndex = !initial && MusicService.savedIndex > 0;
            if (!MusicService.searching && MusicService.resultsQuery !== query) {
                MusicService.search(query);
            } else if (root._restoreIndex && resultsView.count > 0) {
                // Results for this query are already here: apply now.
                root._restoreIndex = false;
                resultsView.currentIndex = Math.min(Math.max(MusicService.savedIndex, 0), resultsView.count - 1);
                resultsView.positionViewAtIndex(resultsView.currentIndex, ListView.Contain);
            }
        } else {
            MusicService.refreshLibrary();
        }
        inputField.forceActiveFocus();
    }
}
