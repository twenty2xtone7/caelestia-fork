pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property var bar
    required property Brightness.Monitor monitor
    property color colour: Colours.palette.m3primary

    readonly property bool horizontal: BarState.horizontal

    readonly property string windowTitle: {
        const title = Hypr.activeToplevel?.title;
        if (!title)
            return Tr.trCtx("Desktop", "shown when no window is focused");
        if (Config.bar.activeWindow.compact) {
            // " - " (standard hyphen), " — " (em dash), " – " (en dash)
            const parts = title.split(/\s+[\-\u2013\u2014]\s+/);
            if (parts.length > 1)
                return parts[parts.length - 1].trim();
        }
        return title;
    }

    // Length available along the bar's main axis, after every other entry.
    readonly property int maxLength: {
        const otherModules = bar.children.filter(c => c.entryId && c.item !== this && c.entryId !== "spacer");
        const otherLength = otherModules.reduce((acc, curr) => acc + (horizontal ? curr.width : (curr.item.nonAnimHeight ?? curr.height)), 0);
        // Length - 2 cause repeater counts as a child
        return (horizontal ? bar.width : bar.height) - otherLength - bar.spacing * (bar.children.length - 1) - bar.vPadding * 2;
    }
    property Title current: text1

    clip: true
    implicitWidth: horizontal ? icon.implicitWidth + Tokens.spacing.small + current.implicitWidth : Math.max(icon.implicitWidth, current.implicitHeight)
    implicitHeight: horizontal ? Math.max(icon.implicitHeight, current.implicitHeight) : icon.implicitHeight + Tokens.spacing.small + current.implicitWidth

    Loader {
        asynchronous: true
        anchors.fill: parent
        active: !Config.bar.activeWindow.showOnHover

        sourceComponent: MouseArea {
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onPositionChanged: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent && popouts.currentName !== "activewindow")
                    popouts.hasCurrent = false;
            }
            onClicked: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent) {
                    popouts.hasCurrent = false;
                } else {
                    popouts.currentName = "activewindow";
                    popouts.currentCenter = root.horizontal ? root.mapToItem(root.bar, root.implicitWidth / 2, 0).x : root.mapToItem(root.bar, 0, root.implicitHeight / 2).y;
                    popouts.hasCurrent = true;
                }
            }
        }
    }

    MaterialIcon {
        id: icon

        x: root.horizontal ? 0 : (parent.width - width) / 2
        y: root.horizontal ? (parent.height - height) / 2 : 0

        animate: true
        text: Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
        color: root.colour
    }

    Title {
        id: text1
    }

    Title {
        id: text2
    }

    TextMetrics {
        id: metrics

        text: root.windowTitle
        font: root.Tokens.font.body.builders.small.letterSpacing(1.4).build()
        elide: Qt.ElideRight
        elideWidth: root.maxLength - (root.horizontal ? icon.width : icon.height)

        onTextChanged: {
            const next = root.current === text1 ? text2 : text1;
            next.text = elidedText;
            root.current = next;
        }
        onElideWidthChanged: root.current.text = elidedText
    }

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }

    component Title: StyledText {
        id: text

        x: root.horizontal ? icon.width + Tokens.spacing.small : (root.width - width) / 2
        y: root.horizontal ? (root.height - height) / 2 : icon.height + Tokens.spacing.small

        font: metrics.font
        color: root.colour
        opacity: root.current === this ? 1 : 0
        horizontalAlignment: Text.AlignLeft

        transform: [
            Translate {
                x: (root.horizontal || !root.Config.bar.activeWindow.inverted) ? 0 : -text.implicitWidth + text.implicitHeight
            },
            Rotation {
                angle: root.horizontal ? 0 : (root.Config.bar.activeWindow.inverted ? 270 : 90)
                origin.x: text.implicitHeight / 2
                origin.y: text.implicitHeight / 2
            }
        ]

        width: root.horizontal ? implicitWidth : implicitHeight
        height: root.horizontal ? implicitHeight : implicitWidth

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
