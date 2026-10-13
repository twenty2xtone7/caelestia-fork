import QtQuick
import Quickshell
import Caelestia.Images

Image {
    id: root

    property string path

    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    source: IUtils.urlForPath(path, fillMode)
    sourceSize: {
        const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
        // Cap at 4K display equivalent to prevent OOM
        const maxWidth = Math.min(width, 3840) * dpr;
        const maxHeight = Math.min(height, 2160) * dpr;
        return Qt.size(maxWidth, maxHeight);
    }
}
