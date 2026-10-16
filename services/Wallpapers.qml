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
        root.appliedWallpaper = true;
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
        else {
            Colours.showPreview = false;
            restorePreviewTerminals();
        }
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear) {
            Colours.showPreview = false;
            restorePreviewTerminals();
        }
    }

    // Re-apply the committed scheme's terminal colors after previewing,
    // unless a wallpaper was applied since (then terminals are already
    // correct and re-blasting them would just flash stale colors).
    function restorePreviewTerminals(): void {
        if (root.appliedWallpaper) {
            root.appliedWallpaper = false;
            return;
        }
        // Preview ends: put terminals back on the committed scheme.
        root.applyTerminalColours(Colours.committedColoursJson);
    }

    // Live terminal sync (dynamic scheme only). The static apply path goes
    // through `caelestia wallpaper -f`, whose apply_colours() broadcasts
    // terminal sequences — but previews and the live-apply path never touch
    // the CLI, so without this terminals would freeze on the old scheme.
    // Sequences mirror the CLI's OSC format (fg/bg/cursor/selection +
    // palette) and are written straight to each pty, same as apply_terms.
    property bool termSyncEnabled: true
    property int termsSeq: 0
    // True once setWallpaper() has run: terminals then already match (or
    // are about to match, via the CLI) the committed scheme, so preview
    // dismissal must NOT "restore" them — that would visibly re-blast the
    // terminals, possibly with a stale pre-apply scheme.
    property bool appliedWallpaper: false

    readonly property string termScript: "import json, os, sys\nfrom pathlib import Path\ntry:\n    colours = json.loads(sys.argv[1])['colours']\n    def esc(*i, c):\n        h = c.lstrip('#')\n        return chr(27) + ']' + ';'.join(map(str, i)) + ';rgb:' + h[0:2] + '/' + h[2:4] + '/' + h[4:6] + chr(7)\n    seq = esc(10, c=colours['onSurface']) + esc(11, c=colours['surface']) + esc(12, c=colours['secondary']) + esc(17, c=colours['secondary'])\n    for n in range(16):\n        seq += esc(4, n, c=colours['term%d' % n])\n    seq += esc(4, 16, c=colours['primary']) + esc(4, 17, c=colours['secondary']) + esc(4, 18, c=colours['tertiary'])\n    data = seq.encode()\n    for pt in Path('/dev/pts').iterdir():\n        if pt.name.isdigit():\n            try:\n                fd = os.open(str(pt), os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)\n                try:\n                    os.write(fd, data)\n                finally:\n                    os.close(fd)\n            except (PermissionError, OSError, BlockingIOError):\n                pass\nexcept Exception:\n    pass\n"

    FileView {
        path: `${Paths.config}/cli.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const cfg = JSON.parse(text());
                root.termSyncEnabled = cfg?.theme?.enableTerm ?? true;
            } catch (e) {
                root.termSyncEnabled = true;
            }
        }
        onLoadFailed: root.termSyncEnabled = true
    }

    Process {
        id: termsApplier
    }

    function applyTerminalColours(jsonText) {
        if (!root.termSyncEnabled || !jsonText)
            return;
        let colours;
        try {
            const parsed = JSON.parse(jsonText);
            colours = parsed?.colours;
        } catch (e) {
            return;
        }
        if (!colours || typeof colours !== "object")
            return;
        root.termsSeq++;
        // termsSeq in argv forces a restart even when the same wallpaper
        // is previewed twice in a row (identical JSON otherwise).
        termsApplier.command = ["python3", "-c", root.termScript, jsonText, String(root.termsSeq)];
        termsApplier.running = true;
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
                root.appliedWallpaper = false;
                root.applyTerminalColours(text);
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
                // Live apply bypasses the CLI, so regenerate + apply
                // terminal colors here (static applies do it via -f).
                Colours.committedColoursJson = text;
                root.applyTerminalColours(text);
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
                root.appliedWallpaper = false;
                root.applyTerminalColours(text);
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
