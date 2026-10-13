pragma ComponentBehavior: Bound

import "cards"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property var props
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property matrix4x4 deformMatrix

    // Cap for the scroll viewport when the parent squeezes us
    // (notification expand-all hands us a 30% strip); -1 means fit content
    // as before. The root itself stays natural-sized so no height feedback
    // loop can form; only the viewport is capped.
    property real maxHeight: -1

    readonly property int enabledCards: (idleInhibit.active ? 1 : 0) + (record.active ? 1 : 0) + (toggles.active ? 1 : 0)
    readonly property real nonAnimHeight: ((idleInhibit.item as IdleInhibit)?.nonAnimHeight ?? 0) + ((record.item as Record)?.nonAnimHeight ?? 0) + ((toggles.item as Toggles)?.implicitHeight ?? 0) + layout.spacing * Math.max(0, enabledCards - 1)

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    StyledFlickable {
        id: view

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: maxHeight > 0 ? Math.min(layout.implicitHeight, maxHeight) : layout.implicitHeight
        contentWidth: width
        contentHeight: layout.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        clip: true

        // NOTE: explicit width, never anchors: this layout lives inside
        // the Flickable's contentItem, where anchors loop back through
        // contentWidth/contentHeight.
        ColumnLayout {
            id: layout

            width: view.width
            spacing: Tokens.spacing.medium

            Loader {
                id: idleInhibit

                Layout.fillWidth: true
                active: Config.utilities.cards.keepAwake
                visible: active

                sourceComponent: IdleInhibit {
                    objectName: "utilitiesKeepAwake"
                }
            }

            Loader {
                id: record

                Layout.fillWidth: true
                active: Config.utilities.cards.recorder
                visible: active
                z: 1

                sourceComponent: Record {
                    objectName: "utilitiesScreenRecorder"

                    props: root.props
                    screenState: root.screenState
                }
            }

            Loader {
                id: toggles

                Layout.fillWidth: true
                active: Config.utilities.cards.quickToggles
                visible: active

                sourceComponent: Toggles {
                    objectName: "utilitiesQuickToggles"

                    screenState: root.screenState
                    popouts: root.popouts
                }
            }
        }
    }

    RecordingDeleteModal {
        props: root.props
        deformMatrix: root.deformMatrix
    }
}
