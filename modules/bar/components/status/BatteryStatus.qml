import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property color colour

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: -Tokens.spacing.extraSmall

        MaterialIcon {
            id: batteryIcon
            Layout.alignment: Qt.AlignHCenter
            animate: true
            text: {
                if (!UPower.displayDevice.isLaptopBattery) {
                    if (PowerProfiles.profile === PowerProfile.PowerSaver)
                        return "energy_savings_leaf";
                    if (PowerProfiles.profile === PowerProfile.Performance)
                        return "rocket_launch";
                    return "balance";
                }
                return Icons.getBatteryIcon(UPower.displayDevice.percentage, [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state));
            }
            color: !UPower.onBattery || UPower.displayDevice.percentage > 0.2 ? colour : Colours.palette.m3error
            fill: 1
        }

        StyledText {
            id: batteryText
            visible: UPower.displayDevice.isLaptopBattery
            Layout.alignment: Qt.AlignHCenter
            text: UPower.displayDevice.isLaptopBattery ? `${Math.round(UPower.displayDevice.percentage * 100)}` : ""
            font.pixelSize: 9
            font.weight: 700
            color: !UPower.onBattery || UPower.displayDevice.percentage > 0.2 ? colour : Colours.palette.m3error
        }
    }
}
