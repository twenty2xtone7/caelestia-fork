pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

// Fan mini-app. The launcher morphs into this view when the
// `/fan` action is selected; the X button or Escape morphs back to the
// action list. RPM/temp poll every second while open.
Item {
    id: root

    required property var screenState
    required property SearchBar search

    signal closeRequested

    // Owns keyboard focus while open so arrows adjust the level and Escape
    // morphs back. The slider itself stays unfocused so native key handling
    // can never desync it from the backend.
    focus: true

    // One wheel notch (120 units) per level step; remainders accumulate so
    // touchpad scrolls don't jump.
    property real wheelAccum: 0

    function backToActions(): void {
        Actions.closeMiniApp();
        search.text = GlobalConfig.launcher.actionPrefix;
        search.forceActiveFocus();
        closeRequested();
    }

    function handleWheel(angleY: real): void {
        wheelAccum += angleY;
        while (wheelAccum >= 120) {
            wheelAccum -= 120;
            FanCtl.nudge(1);
        }
        while (wheelAccum <= -120) {
            wheelAccum += 120;
            FanCtl.nudge(-1);
        }
    }

    implicitWidth: Tokens.sizes.launcher.itemWidth * 1.2
    implicitHeight: layout.implicitHeight

    Component.onCompleted: {
        FanCtl.reload();
        root.forceActiveFocus();
    }

    Keys.onLeftPressed: event => {
        FanCtl.nudge(-1);
        event.accepted = true;
    }
    Keys.onDownPressed: event => {
        FanCtl.nudge(-1);
        event.accepted = true;
    }
    Keys.onRightPressed: event => {
        FanCtl.nudge(1);
        event.accepted = true;
    }
    Keys.onUpPressed: event => {
        FanCtl.nudge(1);
        event.accepted = true;
    }
    Keys.onEscapePressed: backToActions()

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => root.handleWheel(event.angleDelta.y)
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.screenState.launcher
        onTriggered: FanCtl.reload()
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right

        spacing: Tokens.spacing.medium

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "mode_fan"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.large
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                text: Tr.tr("Fan")
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
            }

            StyledText {
                visible: FanCtl.tempText !== ""
                text: FanCtl.tempText
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                Layout.alignment: Qt.AlignVCenter
            }

            IconButton {
                icon: "close"
                type: IconButton.Text
                onClicked: root.backToActions()
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Live readout
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: FanCtl.modeLabel
                font: Tokens.font.headline.small
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            MaterialIcon {
                text: "autorenew"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
                Layout.alignment: Qt.AlignVCenter
                visible: FanCtl.currentLevel === "auto"
            }
        }

        // Level rail: auto - 0..7 - max. Writes on release, never while
        // dragging, so the EC isn't spammed mid-drag.
        StyledSlider {
            id: levelSlider

            Layout.fillWidth: true
            Layout.preferredHeight: 20

            from: 0
            to: 9
            stepSize: 1
            snapStep: 1
            interactionOnMove: false
            focusPolicy: Qt.NoFocus
            value: FanCtl.sliderPos
            onInteraction: v => FanCtl.setSliderPos(Math.round(v * 9))
        }

        // Tick labels
        Row {
            Layout.fillWidth: true

            Repeater {
                model: ["Auto", "0", "1", "2", "3", "4", "5", "6", "7", "Max"]

                StyledText {
                    required property string modelData
                    required property int index

                    text: modelData
                    font: Tokens.font.label.small
                    color: FanCtl.sliderPos === index ? Colours.palette.m3primary : Colours.palette.m3outline
                    width: parent.width / 10
                    horizontalAlignment: index === 0 ? Text.AlignLeft : index === 9 ? Text.AlignRight : Text.AlignHCenter
                }
            }
        }
    }
}
