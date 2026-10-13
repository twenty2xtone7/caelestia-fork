import "weather"
import QtQuick
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property int rootHeight
    // Only refresh while the lock screen is shown; the shell runs 24/7 unlocked
    required property bool locked
    readonly property bool showForecast: rootHeight >= Tokens.sizes.lock.showForecastHeight

    implicitHeight: {
        const base = brief.implicitHeight + brief.anchors.topMargin;
        if (showForecast)
            return base + Tokens.spacing.largeIncreased + forecast.implicitHeight + forecast.anchors.margins;
        return base + brief.anchors.topMargin;
    }
    radius: LiquidGlass.enabled ? LiquidGlass.cornerRadius : Tokens.rounding.extraExtraLarge
    color: Colours.tPalette.m3surfaceContainer

    Timer {
        running: root.locked
        triggeredOnStart: true
        repeat: true
        interval: 900000 // 15 minutes
        onTriggered: Weather.reload()
    }

    BriefInfo {
        id: brief

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Tokens.padding.extraLarge

        rootHeight: root.rootHeight
    }

    Loader {
        id: forecast

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        active: root.showForecast
        asynchronous: true

        sourceComponent: Forecast {}
    }
}
