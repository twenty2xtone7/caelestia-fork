import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property var modelData
    required property var list

    readonly property bool isImage: !!modelData?.isImage
    readonly property string previewPath: ClipboardService.previews[modelData?.id]?.path ?? ""

    function activate(): void {
        if (!modelData)
            return;
        if (ClipboardService.deleteMode)
            ClipboardService.remove(modelData);
        else {
            ClipboardService.copy(modelData);
            list.screenState.launcher = false;
        }
    }

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    Timer {
        id: previewTimer

        // Wait for scroll/typing to settle so fast scrolling queues
        // only the rows you actually stop on instead of every row passed.
        interval: 120
        repeat: false
        onTriggered: {
            if (root.isImage)
                ClipboardService.ensurePreview(root.modelData, false);
        }
    }

    Component.onCompleted: {
        if (isImage)
            previewTimer.start();
    }

    onModelDataChanged: {
        // Delegates are recycled while scrolling; the new row needs
        // its own thumbnail request.
        if (isImage)
            previewTimer.restart();
        else
            previewTimer.stop();
    }

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: root.activate()
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        StyledClippingRect {
            id: thumb

            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: parent.height * 0.8
            implicitHeight: parent.height * 0.8
            radius: Tokens.rounding.small
            color: Colours.tPalette.m3surfaceContainerHighest

            MaterialIcon {
                anchors.centerIn: parent
                visible: img.status !== Image.Ready
                text: root.isImage ? "image" : root.modelData?.isBinary ? "data_object" : "content_paste"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
            }

            Image {
                id: img

                anchors.fill: parent
                visible: root.isImage
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                source: (ClipboardService.imagesReady && root.previewPath) ? `file://${root.previewPath}` : ""
                sourceSize: {
                    const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                    return Qt.size(thumb.implicitWidth * dpr, thumb.implicitHeight * dpr);
                }
            }
        }

        Item {
            anchors.left: thumb.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: thumb.verticalCenter

            implicitHeight: name.implicitHeight + desc.implicitHeight

            StyledText {
                id: name

                anchors.left: parent.left
                anchors.right: parent.right
                elide: Text.ElideRight
                font: Tokens.font.body.medium
                text: {
                    if (root.isImage)
                        return root.modelData.width ? `${root.modelData.ext.toUpperCase()} · ${root.modelData.width}×${root.modelData.height}` : (root.modelData.ext || "image").toUpperCase();
                    if (root.modelData?.isBinary)
                        return root.modelData.preview;
                    const t = (root.modelData?.preview ?? "").slice(0, 300).replace(/\s+/g, " ").trim();
                    return t || "Empty";
                }
            }

            StyledText {
                id: desc

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: name.bottom
                elide: Text.ElideRight
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
                text: {
                    if (root.isImage)
                        return root.modelData.sizeKiB ? `${root.modelData.sizeKiB} KiB` : "Image";
                    if (root.modelData?.isBinary)
                        return "Binary";
                    const n = (root.modelData?.preview ?? "").length;
                    return n ? `${n} chars` : "Text";
                }
            }
        }
    }
}
