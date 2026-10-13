pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Models
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus

ColumnLayout {
    id: root

    required property var props
    required property ScreenState screenState

    // Hidden when embedded in Nexus itself (would open a second window).
    property bool showSettingsButton: true
    // Fixed visible row count. 0 keeps the legacy compact heights.
    property int listRows: 0
    // When true, the play button emits playRequested(path) for an inline
    // player instead of launching the external playback app. Nexus uses
    // this; the sidebar card keeps the external player.
    property bool inlinePlayback: false

    signal playRequested(string path)

    spacing: 0

    WrapperMouseArea {
        Layout.fillWidth: true

        cursorShape: Qt.PointingHandCursor
        onClicked: root.props.recordingListExpanded = !root.props.recordingListExpanded

        RowLayout {
            spacing: Tokens.spacing.medium

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "list"
                fontStyle: Tokens.font.icon.large
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                text: Tr.tr("Recordings")
                font: Tokens.font.body.medium
            }

            IconButton {
                icon: root.props.recordingListExpanded ? "unfold_less" : "unfold_more"
                type: IconButton.Text
                label.animate: true
                onClicked: root.props.recordingListExpanded = !root.props.recordingListExpanded
            }
        }
    }

    StyledListView {
        id: list

        model: FileSystemModel {
            path: Paths.recsdir
            nameFilters: ["recording_*.mp4"]
            sortReverse: true
        }

        Layout.fillWidth: true
        Layout.rightMargin: -Tokens.spacing.small
        implicitHeight: root.listRows > 0 ? root.listRows * 76 : (Tokens.font.body.large.pointSize + Tokens.padding.small) * (root.props.recordingListExpanded ? 10 : 3)
        clip: true

        spacing: Tokens.spacing.extraSmall

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }

        delegate: StyledRect {
            id: recording

            required property FileSystemEntry modelData
            property string baseName
            property string thumbPath: ""
            property bool thumbFailed: false

            anchors.left: list.contentItem.left
            anchors.right: list.contentItem.right
            anchors.rightMargin: Tokens.spacing.small
            implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins * 2
            radius: Tokens.rounding.large
            color: "transparent"

            Component.onCompleted: {
                baseName = modelData.baseName;
                ensureThumb();
            }

            function thumbFile(): string {
                return `${Paths.cache}/record-thumbs/${modelData.baseName}.png`;
            }

            function ensureThumb(): void {
                if (thumbPath || thumbFailed || thumbProc.running)
                    return;
                const out = thumbFile();
                thumbProc.exec(["sh", "-c", `mkdir -p "$1" && { test -s "$2" || ffmpeg -y -v error -ss 1 -i "$3" -frames:v 1 "$2"; } && test -s "$2"`, "thumb", `${Paths.cache}/record-thumbs`, out, modelData.path]);
            }

            Process {
                id: thumbProc

                onExited: exitCode => {
                    if (exitCode === 0)
                        recording.thumbPath = recording.thumbFile();
                    else
                        recording.thumbFailed = true;
                }
            }

            RowLayout {
                id: rowLayout

                anchors.fill: parent
                anchors.margins: Tokens.spacing.small
                spacing: Tokens.spacing.medium

                StyledClippingRect {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    Layout.alignment: Qt.AlignVCenter
                    radius: Tokens.rounding.small
                    color: Colours.tPalette.m3surfaceContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: thumbImg.status !== Image.Ready
                        text: "movie"
                        color: Colours.tPalette.m3outline
                        fontStyle: Tokens.font.icon.medium
                    }

                    Image {
                        id: thumbImg

                        anchors.fill: parent
                        asynchronous: false
                        fillMode: Image.PreserveAspectCrop
                        source: recording.thumbPath ? `file://${recording.thumbPath}` : ""
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: recording.baseName
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            Time.date; // re-evaluate as time passes so the label ages live
                            const time = recording.baseName;
                            const matches = time.match(/^recording_(\d{4})(\d{2})(\d{2})_(\d{2})-(\d{2})-(\d{2})/);
                            if (!matches)
                                return time;
                            const date = new Date(...matches.slice(1));
                            date.setMonth(date.getMonth() - 1); // Woe (months start from 0)
                            const secs = Math.max(0, Math.floor((Time.date.getTime() - date.getTime()) / 1000));
                            if (secs < 60)
                                return Tr.tr("Just recorded now");
                            const mins = Math.floor(secs / 60);
                            if (mins < 60)
                                return Tr.trN("%n minute ago", "%n minutes ago", mins);
                            const hours = Math.floor(mins / 60);
                            if (hours < 24)
                                return Tr.trN("%n hour ago", "%n hours ago", hours);
                            if (hours < 48)
                                return Tr.tr("Yesterday");
                            return Tr.tr("Recording at %1").arg(Qt.formatDateTime(date, Qt.locale()));
                        }
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    icon: "play_arrow"
                    type: IconButton.Text
                    font: Tokens.font.icon.small
                    onClicked: {
                        if (root.inlinePlayback) {
                            root.playRequested(recording.modelData.path);
                            return;
                        }
                        root.screenState.utilities = false;
                        root.screenState.sidebar = false;
                        Quickshell.execDetached([...GlobalConfig.general.apps.playback, recording.modelData.path]);
                    }
                }

                IconButton {
                    icon: "content_copy"
                    type: IconButton.Text
                    font: Tokens.font.icon.small
                    onClicked: {
                        // Real file URI (not a path): Ctrl+V sends it in
                        // Telegram and pastes a copy in file managers.
                        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | wl-copy --type text/uri-list", "clip", `file://${recording.modelData.path}`]);
                        Toaster.toast(Tr.tr("Recording copied"), Tr.tr("Paste it into Telegram or a file manager"), "content_copy");
                    }
                }

                IconButton {
                    icon: "folder"
                    type: IconButton.Text
                    font: Tokens.font.icon.small
                    onClicked: {
                        root.screenState.utilities = false;
                        root.screenState.sidebar = false;
                        Quickshell.execDetached([...GlobalConfig.general.apps.explorer, recording.modelData.path]);
                    }
                }

                IconButton {
                    icon: "delete_forever"
                    type: IconButton.Text
                    font: Tokens.font.icon.small
                    label.color: Colours.palette.m3error
                    stateLayer.color: Colours.palette.m3error
                    onClicked: root.props.recordingConfirmDelete = recording.modelData.path
                }
            }
        }

        add: Transition {
            Anim {
                type: Anim.DefaultEffects
                property: "opacity"
                from: 0
                to: 1
            }
        }

        remove: Transition {
            Anim {
                type: Anim.DefaultEffects
                property: "opacity"
                to: 0
            }
        }

        displaced: Transition {
            Anim {
                type: Anim.DefaultEffects
                property: "opacity"
                to: 1
            }
            Anim {
                property: "y"
            }
        }

        Loader {
            asynchronous: false
            anchors.centerIn: parent

            opacity: list.count === 0 ? 1 : 0
            active: opacity > 0

            sourceComponent: ColumnLayout {
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "scan_delete"
                    color: Colours.palette.m3outline
                    fontStyle: Tokens.font.icon.extraLarge

                    opacity: root.props.recordingListExpanded ? 1 : 0
                    scale: root.props.recordingListExpanded ? 1 : 0
                    Layout.preferredHeight: root.props.recordingListExpanded ? implicitHeight : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    Behavior on scale {
                        Anim {}
                    }

                    Behavior on Layout.preferredHeight {
                        Anim {}
                    }
                }

                RowLayout {
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "scan_delete"
                        color: Colours.palette.m3outline

                        opacity: !root.props.recordingListExpanded ? 1 : 0
                        scale: !root.props.recordingListExpanded ? 1 : 0
                        Layout.preferredWidth: !root.props.recordingListExpanded ? implicitWidth : 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        Behavior on scale {
                            Anim {}
                        }

                        Behavior on Layout.preferredWidth {
                            Anim {}
                        }
                    }

                    StyledText {
                        text: Tr.tr("No recordings found")
                        color: Colours.palette.m3outline
                    }
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Behavior on implicitHeight {
            Anim {}
        }
    }

    IconTextButton {
        visible: root.showSettingsButton
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        inactiveColour: Colours.palette.m3primaryContainer
        inactiveOnColour: Colours.palette.m3onPrimaryContainer
        verticalPadding: Tokens.padding.extraSmall
        text: Tr.tr("Open settings")
        icon: "settings"

        onClicked: {
            root.screenState.utilities = false;
            root.screenState.sidebar = false;
            // PageRegistry index of the Recordings page.
            WindowFactory.startPage = 10;
            WindowFactory.create();
        }
    }
}
