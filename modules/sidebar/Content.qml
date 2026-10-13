import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    required property Props props
    required property ScreenState screenState

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        GlassSurface {
            Layout.fillWidth: true
            Layout.fillHeight: true

            radiusGroup: "card"
            componentName: "sidebar"
            color: Colours.tPalette.m3surfaceContainerLow

            NotifDock {
                objectName: "sidebarNotifications"

                props: root.props
                screenState: root.screenState
            }
        }

        StyledRect {
            Layout.topMargin: Tokens.padding.large - layout.spacing
            Layout.fillWidth: true
            implicitHeight: 1

            color: Colours.tPalette.m3outlineVariant
        }
    }
}
