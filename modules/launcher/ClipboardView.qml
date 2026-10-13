pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.launcher.services
import qs.modules.launcher.items

Item {
    id: root

    required property var screenState
    required property SearchBar search

    readonly property alias list: resultsView
    readonly property var currentEntry: resultsView.currentItem?.modelData ?? null
    property bool previewExpanded: false
    // Debounced copy of the search text: filtering + selection reset +
    // preview decode only run once typing pauses instead of per keystroke.
    property string filterText: ""
    // Temporary open-latency instrumentation (remove once diagnosed).
    property double _createdAt: 0
    property bool _loggedModel: false
    property bool _loggedPreview: false

    Timer {
        id: filterTimer

        interval: 120
        repeat: false
        onTriggered: root.filterText = root.search.text
    }

    Timer {
        id: imagesTimer

        // Let the open animation finish before any image source resolves,
        // so texture uploads can't stall view creation.
        interval: 200
        repeat: false
        onTriggered: {
            ClipboardService.imagesReady = true;
            console.info(`[clip-perf] images-ready +${Date.now() - ClipboardService._openAt}ms`);
        }
    }

    Connections {
        target: root.search
        function onTextChanged(): void {
            filterTimer.restart();
        }
    }

    onCurrentEntryChanged: {
        if (!currentEntry?.isImage)
            previewExpanded = false;
    }

    implicitWidth: Tokens.sizes.launcher.itemWidth * 1.35
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: ClipboardService.deleteMode ? "delete" : "content_paste"
                color: ClipboardService.deleteMode ? Colours.palette.m3error : Colours.palette.m3primary
                fontStyle: Tokens.font.icon.large
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: ClipboardService.deleteMode ? Tr.tr("Delete from clipboard") : Tr.tr("Clipboard")
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
            }

            StyledText {
                visible: ClipboardService.loading
                text: Tr.tr("Loading…")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            IconButton {
                icon: "delete"
                type: IconButton.Text
                isToggle: true
                checked: ClipboardService.deleteMode
                onClicked: ClipboardService.deleteMode = !ClipboardService.deleteMode
            }
        }

        StyledText {
            visible: resultsView.count === 0 && !ClipboardService.loading
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: search.text.trim() ? Tr.tr("No clipboard matches") : Tr.tr("Clipboard history is empty")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledListView {
                id: resultsView

                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(0, Math.min(count, Config.launcher.maxShown) * (Tokens.sizes.launcher.itemHeight + spacing) - spacing)
                visible: count > 0

                property var screenState: root.screenState

                spacing: Tokens.spacing.small
                orientation: Qt.Vertical
                clip: true
                preferredHighlightBegin: 0
                preferredHighlightEnd: height
                highlightRangeMode: ListView.ApplyRange
                model: ScriptModel {
                    values: {
                        ClipboardService.entries;
                        return ClipboardService.query(root.filterText);
                    }
                    onValuesChanged: resultsView.currentIndex = 0
                }
                delegate: ClipboardItem {
                    list: resultsView
                }

                highlightMoveDuration: 200
                highlightFollowsCurrentItem: true
                highlight: StyledRect {
                    radius: Tokens.rounding.large
                    color: ClipboardService.deleteMode ? Colours.palette.m3error : Colours.palette.m3onSurface
                    opacity: 0.08

                    y: resultsView.currentItem?.y ?? 0
                    implicitWidth: resultsView.width
                    implicitHeight: resultsView.currentItem?.implicitHeight ?? 0

                    Behavior on y {
                        Anim {}
                    }
                }

                onCurrentIndexChanged: {
                    const e = currentItem?.modelData;
                    if (e?.isImage)
                        ClipboardService.ensurePreview(e, true);
                }

                onCountChanged: {
                    if (!root._loggedModel) {
                        root._loggedModel = true;
                        console.info(`[clip-perf] model-ready count=${count} +${Date.now() - ClipboardService._openAt}ms`);
                    }
                }

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: resultsView
                }
            }

            StyledClippingRect {
                visible: !!root.currentEntry?.isImage
                Layout.preferredWidth: Tokens.sizes.launcher.itemHeight * 3.2
                Layout.preferredHeight: Tokens.sizes.launcher.itemHeight * 3.2
                Layout.alignment: Qt.AlignTop
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                StateLayer {
                    radius: parent?.radius ?? 0
                    onClicked: {
                        if (root.currentEntry?.isImage)
                            root.previewExpanded = true;
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: previewImg.status !== Image.Ready
                    text: "image"
                    color: Colours.tPalette.m3outline
                    fontStyle: Tokens.font.icon.extraLarge
                    z: -1
                }

                Image {
                    id: previewImg

                    anchors.fill: parent
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    onStatusChanged: {
                        if (status === Image.Ready && !root._loggedPreview) {
                            root._loggedPreview = true;
                            console.info(`[clip-perf] first-preview +${Date.now() - ClipboardService._openAt}ms`);
                        }
                    }
                    source: {
                        if (!ClipboardService.imagesReady)
                            return "";
                        const id = root.currentEntry?.id;
                        const path = id ? (ClipboardService.previews[id]?.path ?? "") : "";
                        return path ? `file://${path}` : "";
                    }
                    sourceSize: {
                        const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                        return Qt.size(width * dpr, height * dpr);
                    }
                }
            }
        }
    }

    StyledClippingRect {
        visible: root.previewExpanded && !!root.currentEntry?.isImage
        anchors.fill: parent
        z: 10
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        StateLayer {
            radius: parent?.radius ?? 0
            onClicked: root.previewExpanded = false
        }

        Image {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            source: {
                if (!ClipboardService.imagesReady)
                    return "";
                const id = root.currentEntry?.id;
                const path = id ? (ClipboardService.previews[id]?.path ?? "") : "";
                return path ? `file://${path}` : "";
            }
            sourceSize: {
                const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                return Qt.size(width * dpr, height * dpr);
            }
        }

        IconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Tokens.padding.small
            icon: "close"
            type: IconButton.Text
            onClicked: root.previewExpanded = false
        }
    }

    Component.onCompleted: {
        ClipboardService.reload();
        imagesTimer.start();
        root._createdAt = Date.now();
        console.info(`[clip-perf] open->view-created ${root._createdAt - ClipboardService._openAt}ms`);
        const initial = Actions.miniAppInitialText || "";
        if (search.text !== initial)
            search.text = initial;
        root.filterText = search.text;
        search.forceActiveFocus();
    }
}
