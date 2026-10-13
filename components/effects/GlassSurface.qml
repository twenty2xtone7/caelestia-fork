import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Shared Liquid Glass material for cards, controls, menus, and the
// settings preview. Backdrop blur is Hyprland's, not a per-card effect.
StyledRect {
    id: root

    property string radiusGroup: "card"
    property string componentName: ""
    property int elevation: 0

    readonly property real glassRadius: {
        if (!LiquidGlass.enabled)
            return Tokens.rounding.large;
        if (root.componentName)
            return LiquidGlass.effectiveValue("cardRadius", root.componentName);
        return LiquidGlass.radius(root.radiusGroup);
    }

    radius: glassRadius
    border.width: LiquidGlass.enabled ? 1 : 0
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, LiquidGlass.borderOpacity)

    Behavior on radius {
        Anim {
            type: Anim.SlowEffects
        }
    }

    Behavior on border.color {
        CAnim {}
    }

    Elevation {
        anchors.fill: parent
        z: -1
        radius: root.radius
        level: root.elevation
        visible: LiquidGlass.enabled && root.elevation > 0
        color: Qt.alpha(Colours.palette.m3shadow, LiquidGlass.shadowOpacity)
        blur: (dp * 5) ** 0.7 * (LiquidGlass.shadowBlur / 15)
    }

    // Specular top edge — communicates glass thickness without a heavy border.
    Rectangle {
        enabled: false
        visible: LiquidGlass.enabled && LiquidGlass.highlightOpacity > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Math.max(4, root.radius * 0.35)
        anchors.rightMargin: Math.max(4, root.radius * 0.35)
        height: 1
        radius: 1
        color: Qt.alpha("#ffffff", LiquidGlass.highlightOpacity)
        z: 0
    }

    // Faint inner rim.
    Rectangle {
        enabled: false
        visible: LiquidGlass.enabled && LiquidGlass.innerHighlight
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha("#ffffff", LiquidGlass.highlightOpacity * 0.35)
        z: 0
    }
}
