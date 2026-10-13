pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    function isLive(path: string): bool {
        return /\.(mp4|webm|mkv|mov|avi|m4v)$/i.test(path || "");
    }

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property string staticCurrent: ""
    property string liveCurrent: ""
    property bool previewColourLock
    property bool pendingPreviewClear

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        if (isLive(path)) {
            liveCurrent = path;
            Qt.callLater(() => livePathStorage.setText(path));
            // Extract colors from video if dynamic scheme is enabled
            if (Colours.scheme === "dynamic" && root.smartArg.length === 0) {
                root.videoPathForExtraction = path;
                videoColorExtractor.running = true;
            }
        } else {
            staticCurrent = path;
            liveCurrent = "";
            Qt.callLater(() => livePathStorage.setText(""));
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
        }
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic") {
            if (isLive(path)) {
                root.videoPathForPreview = path;
                previewColorExtractor.running = true;
            } else {
                getPreviewColoursProc.running = true;
            }
        }
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        id: staticPathStorage

        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.staticCurrent = wall;
            if (!root.liveCurrent)
                root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.staticCurrent = root.fallback;
            if (!root.liveCurrent)
                root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileView {
        id: livePathStorage

        path: `${Paths.state}/wallpaper/live-path.txt`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const wall = text().trim();
            if (wall) {
                root.liveCurrent = wall;
                root.actualCurrent = wall;
                // Extract colors for dynamic scheme
                if (Colours.scheme === "dynamic" && root.smartArg.length === 0) {
                    root.videoPathForExtraction = wall;
                    videoColorExtractor.running = true;
                }
            } else if (root.liveCurrent) {
                // cleared externally: fall back to the last static wallpaper/default.
                root.liveCurrent = "";
                root.actualCurrent = root.staticCurrent || root.fallback;
            }
        }
        onLoadFailed: {
            Qt.callLater(() => setText(""));
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Files
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp", "*.tif", "*.tiff", "*.mp4", "*.webm", "*.mkv", "*.mov", "*.avi", "*.m4v"]
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }

    property string videoPathForExtraction: ""
    property string videoPathForPreview: ""

    // Map of video paths to thumbnail paths
    property var videoThumbnails: ({})
    property var pendingThumbnails: ({})
    property int thumbnailUpdateCounter: 0  // Force binding updates
    
    signal thumbnailReady(string videoPath)

    Process {
        id: videoColorExtractor

        command: [
            "bash", "-c",
            `ffmpeg -y -i "${root.videoPathForExtraction}" -ss 00:00:01 -vframes 1 -q:v 2 /tmp/caelestia-video-frame.jpg 2>/dev/null && caelestia wallpaper -p /tmp/caelestia-video-frame.jpg ${root.smartArg.join(" ")}`
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, false);
            }
        }
    }

    Process {
        id: previewColorExtractor

        command: [
            "bash", "-c",
            `ffmpeg -y -i "${root.videoPathForPreview}" -ss 00:00:01 -vframes 1 -q:v 2 /tmp/caelestia-video-frame-preview.jpg 2>/dev/null && caelestia wallpaper -p /tmp/caelestia-video-frame-preview.jpg ${root.smartArg.join(" ")}`
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }

    Component {
        id: thumbnailExtractorComponent

        Process {
            required property string videoPath
            required property string thumbPath

            command: [
                "ffmpeg", "-y", "-i", videoPath,
                "-ss", "00:00:01", "-vframes", "1", "-q:v", "2",
                thumbPath
            ]
            stdout: StdioCollector {}
            stderr: StdioCollector {}

            onRunningChanged: {
                if (!running && (typeof exitCode !== "undefined") && exitCode === 0) {
                    Qt.callLater(() => {
                        delete root.pendingThumbnails[videoPath];
                        root.thumbnailReady(videoPath);
                    });
                }
            }
        }
    }

    // Pre-populate thumbnails from existing files
    Component.onCompleted: {
        for (let i = 0; i < wallpapers.count; i++) {
            const entry = wallpapers.get(i);
            if (isLive(entry.path)) {
                getVideoThumbnail(entry.path);
            }
        }
    }

    function getVideoThumbnail(videoPath) {
        if (!isLive(videoPath)) return videoPath;
        
        // Already cached
        if (videoThumbnails[videoPath]) {
            return videoThumbnails[videoPath];
        }
        
        // Already pending
        if (pendingThumbnails[videoPath]) {
            return pendingThumbnails[videoPath];
        }
        
        // Generate thumbnail path
        const thumbPath = `/tmp/caelestia-thumb-${videoPath.split('/').pop().replace(/\.[^.]+$/, '')}.jpg`;
        
        // Mark as pending
        pendingThumbnails[videoPath] = thumbPath;
        
        // Create process instance to generate thumbnail
        const proc = thumbnailExtractorComponent.createObject(root, {
            videoPath: videoPath,
            thumbPath: thumbPath
        });
        
        proc.running = true;
        
        // Return path even if not yet generated
        return thumbPath;
    }
}
