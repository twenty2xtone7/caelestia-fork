import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Short intro line shown under a Nexus page title. Text is inherited from
// StyledText, so callers just set `text:`.
StyledText {
    Layout.fillWidth: true
    Layout.leftMargin: Tokens.padding.small
    Layout.bottomMargin: Tokens.spacing.extraSmall

    color: Colours.palette.m3onSurfaceVariant
    font: Tokens.font.body.small
    wrapMode: Text.WordWrap
}