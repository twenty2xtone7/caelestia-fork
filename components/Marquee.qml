pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components

// Simple marquee: scrolls text right-to-left when it overflows.
// Stationary when text fits. Reuses Caelestia's Anim easing conventions.
Item {
    id: root
    objectName: "marquee"

    property string text: ""
    property color color: Colours.palette.m3onSurface
    property var font: Tokens.font.body.builders.small.letterSpacing(1.2).build()
    property real speed: 60  // pixels per second
    property bool running: false

    clip: true
    implicitHeight: text1.implicitHeight

    readonly property bool overflows: text1.implicitWidth > width
    readonly property real loopWidth: text1.implicitWidth + 100 // text + gap

    NumberAnimation on scrollOffset {
        id: scrollAnim
        from: 0
        to: -root.loopWidth
        duration: root.loopWidth / root.speed * 1000
        loops: Animation.Infinite
        running: root.running && root.overflows
    }

    property real scrollOffset: 0

    onOverflowsChanged: if (!overflows) scrollOffset = 0;

    StyledText {
        id: text1
        text: root.text
        font: root.font
        color: root.color
        anchors.verticalCenter: parent.verticalCenter
        x: root.overflows ? root.scrollOffset : (parent.width - implicitWidth) / 2
    }

    StyledText {
        id: text2
        text: root.text
        font: root.font
        color: root.color
        anchors.verticalCenter: parent.verticalCenter
        x: text1.x + root.loopWidth
        visible: root.overflows && root.running
    }
}
