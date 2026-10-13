pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.nexus.common
import qs.modules.utilities
import qs.modules.utilities.cards

Item {
    id: root

    property NexusState nState

    // Local stand-ins for the sidebar's shared props: expanded by
    // default here, and deletes are confirmed by the modal below.
    QtObject {
        id: recProps

        property bool recordingListExpanded: true
        property string recordingConfirmDelete: ""
    }

    readonly property var screenState: ShellState.forActive()

    PageBase {
        id: page

        anchors.fill: parent
        title: Tr.tr("Recordings")
        nState: root.nState

        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            width: page.cappedWidth
            spacing: Tokens.spacing.extraSmall / 2

            VideoPlayer {
                id: player

                Layout.fillWidth: true
            }

            RecordingList {
                Layout.fillWidth: true
                props: recProps
                screenState: root.screenState
                showSettingsButton: false
                listRows: 12
                inlinePlayback: true
                onPlayRequested: path => player.play(path)
            }
        }
    }

    RecordingDeleteModal {
        anchors.fill: parent
        props: recProps
        deformMatrix: Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    }
}
