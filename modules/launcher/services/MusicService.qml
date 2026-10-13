pragma Singleton

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.utils

// Music backend service — persistent Python process, JSON-lines protocol.
// Transport: Process.write() -> stdin, SplitParser(onRead) <- stdout lines.
// Playback: persistent MediaPlayer owned here so audio survives the
// ephemeral launcher UI.
Singleton {
    id: root

    // ── Public state ──────────────────────────────────────────────
    property bool ready: false
    property bool searching: false
    property bool downloading: false
    property bool resolving: false
    property list<var> results: []
    property string error: ""
    property string downloadProgress: ""
    property string downloadTitle: ""

    // Playback state (mirrors player below)
    property string currentUrl: ""
    property string currentTitle: ""
    property string currentArtist: ""
    property string currentThumbnail: ""
    property bool isPlaying: false
    property bool isPaused: false
    property real playbackPosition: 0
    property real playbackDuration: 0
    property real volume: 0.8
    property bool repeat: false

    // Library
    property list<var> library: []

    // Play queue ("Up next"). Entries are normalized to
    // {title, artist, webpage_url, thumbnail, duration, path}.
    property list<var> queue: []
    // Entry shifted off the queue while its remote URL resolves; put
    // back at the front if resolving fails so it isn't lost.
    property var _advancing: null

    // Dependencies
    property list<string> missingDeps: []
    property bool depsChecked: false
    property bool depsNotified: false

    // Internal: stale-response guard for debounced searches
    property int _searchGeneration: 0
    property int _appliedSearchGeneration: 0
    property string _pendingSearchQuery: ""
    property string _pendingQuery: ""

    // Last music UI state, so closing the launcher mid-task (searching or
    // not) restores exactly where the user left off on reopen.
    property string savedQuery: ""
    property int savedIndex: 0
    property string resultsQuery: ""
    property bool leftInMusic: false

    // Effective track length in ms: the player often doesn't know the
    // duration of a remote stream, so fall back to the search result's.
    readonly property real seekableLengthMs: player.duration > 0 ? player.duration : pendingLengthUs / 1000
    // MPRIS publish state (backend owns org.mpris.MediaPlayer2.caelestia)
    property int mprisSerial: 0
    property double pendingLengthUs: 0
    property string pendingArtUrl: ""
    property string pendingUrl: ""
    property string _pendingWebpageUrl: ""

    Timer {
        id: searchDebounce
        interval: 400
        repeat: false
        onTriggered: root.search(root._pendingSearchQuery)
    }

    // ── Persistent player ─────────────────────────────────────────
    MediaPlayer {
        id: player

        audioOutput: AudioOutput {
            id: audioOut
            volume: root.volume
        }

        // Loop the current track when repeat is enabled
        loops: root.repeat ? MediaPlayer.Infinite : MediaPlayer.Once

        onPlaybackStateChanged: {
            root.isPlaying = playbackState === MediaPlayer.PlayingState;
            root.isPaused = playbackState === MediaPlayer.PausedState;
            root.pushMprisState();
        }
        onPositionChanged: root.playbackPosition = position
        onDurationChanged: {
            root.playbackDuration = duration;
            if (duration > 0 && (root.isPlaying || root.isPaused))
                root.pushMprisState();
        }
        onErrorOccurred: (error, errorString) => {
            // qmllint disable signal-handler-parameters
            root.error = errorString || Tr.tr("Playback failed");
            root.isPlaying = false;
            Toaster.toast(Tr.tr("Playback failed"), root.error, "error", Toast.Error);
        }
        onMediaStatusChanged: {
            // Natural end of track: advance unless repeat-one is looping it.
            if (mediaStatus === MediaPlayer.EndOfMedia && !root.repeat)
                root.playQueueIndex(0);
        }
    }

    // ── Backend process ───────────────────────────────────────────
    Process {
        id: backend

        running: false
        stdinEnabled: true
        command: ["python3", `${Quickshell.shellDir}/modules/launcher/services/music/backend.py`]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handleLine(data) // qmllint disable signal-handler-parameters
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("[MusicService] backend stderr:", text.trim().slice(0, 300));
            }
        }

        onRunningChanged: {
            if (!running) {
                root.ready = false;
                if (!root.depsNotified)
                    root.error = Tr.tr("Music backend stopped");
            }
        }
    }

    // ── Message dispatch ──────────────────────────────────────────
    function handleLine(data: string): void {
        const line = (data || "").trim();
        if (!line)
            return;
        let msg = null;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            console.warn("[MusicService] Bad JSON:", line.slice(0, 200));
            return;
        }
        handleMessage(msg);
    }

    function handleMessage(msg: var): void {
        switch (msg.type) {
        case "search_partial":
            // Interim hits from an in-flight search: paint them unless a
            // newer search has already superseded this generation.
            if (msg.generation !== undefined && msg.generation !== root._searchGeneration)
                return;
            root.results = msg.results || [];
            root.error = "";
            break;
        case "search_results":
            // Drop stale results: only the latest generation applies.
            if (msg.generation !== undefined && msg.generation !== root._searchGeneration)
                return;
            root.searching = false;
            root._appliedSearchGeneration = root._searchGeneration;
            root.results = msg.results || [];
            root.resultsQuery = root._pendingQuery;
            root.error = msg.error || "";
            break;
        case "search_cancelled":
            root.searching = false;
            break;
        case "resolved":
            root.resolving = false;
            if (msg.url) {
                root._advancing = null;
                root.currentUrl = msg.url;
                root.mprisSerial++;
                root.pendingUrl = root._pendingWebpageUrl;
                player.source = msg.url;
                player.play();
                root.pushMprisState();
                Toaster.toast(Tr.tr("Now playing"), `${root.currentArtist} — ${root.currentTitle}`, "music_note");
            } else {
                // A queued entry that fails to resolve goes back to the
                // front instead of being silently dropped.
                if (root._advancing) {
                    queue = [root._advancing].concat(queue);
                    root._advancing = null;
                    root.pushMprisState();
                }
                root.error = Tr.tr("No playable URL found");
            }
            break;
        case "download_progress":
            root.downloadProgress = msg.percent || "0";
            root.downloadTitle = msg.title || "";
            break;
        case "download_complete":
            root.downloading = false;
            root.downloadProgress = "";
            root.downloadTitle = "";
            Toaster.toast(Tr.tr("Download complete"), msg.title || "", "download_done", Toast.Success);
            refreshLibrary();
            break;
        case "download_error":
            root.downloading = false;
            root.downloadProgress = "";
            root.downloadTitle = "";
            Toaster.toast(Tr.tr("Download failed"), msg.error || "", "error", Toast.Error);
            break;
        case "library":
            root.library = msg.tracks || [];
            break;
        case "deps":
            root.depsChecked = true;
            root.missingDeps = msg.missing || [];
            if (root.missingDeps.length > 0) {
                root.error = Tr.tr("Missing: %1").arg(root.missingDeps.join(", "));
                if (!root.depsNotified) {
                    root.depsNotified = true;
                    Toaster.toast(Tr.tr("Music needs dependencies"), root.missingDeps.join(", "), "error", Toast.Error);
                }
            }
            break;
        case "error":
            root.searching = false;
            root.resolving = false;
            // Keep download state machine intact: download errors arrive
            // as download_error, not generic error.
            root.error = msg.error || "";
            break;
        case "mpris_command":
            handleMprisCommand(msg);
            break;
        }
    }

    // ── Commands ──────────────────────────────────────────────────
    function sendCmd(cmd: var): void {
        if (!backend.running)
            backend.running = true;
        backend.write(JSON.stringify(cmd) + "\n");
    }

    function search(query: string): void {
        const q = (query || "").trim();
        if (!q) {
            root.results = [];
            root.error = "";
            root.searching = false;
            root._pendingQuery = "";
            root.resultsQuery = "";
            return;
        }
        root._searchGeneration++;
        root._pendingQuery = q;
        root.searching = true;
        root.error = "";
        sendCmd({ action: "search", query: q, generation: root._searchGeneration });
    }

    function debouncedSearch(query: string): void {
        root._pendingSearchQuery = query || "";
        searchDebounce.restart();
    }

    function resolveAndPlay(result: var): void {
        if (!result || !result.webpage_url) {
            root.error = Tr.tr("No URL to play");
            return;
        }
        root.resolving = true;
        root.error = "";
        root.currentTitle = result.title || Tr.tr("Unknown");
        root.currentArtist = result.artist || Tr.tr("Unknown");
        root.currentThumbnail = result.thumbnail || "";
        root.pendingArtUrl = result.thumbnail || "";
        root._pendingWebpageUrl = result.webpage_url;
        root.pendingLengthUs = (result.duration || 0) * 1000000;
        sendCmd({ action: "resolve", url: result.webpage_url });
    }

    function playLocal(path: string, title: string, artist: string): void {
        if (!path)
            return;
        root.currentTitle = title || path.split("/").pop();
        root.currentArtist = artist || "";
        root.currentThumbnail = "";
        root.pendingArtUrl = "";
        root._pendingWebpageUrl = "";
        root.pendingUrl = `file://${path}`;
        root.pendingLengthUs = 0;
        root.currentUrl = root.pendingUrl;
        root.error = "";
        root.mprisSerial++;
        player.source = root.currentUrl;
        player.play();
        root.pushMprisState();
        Toaster.toast(Tr.tr("Now playing"), `${root.currentArtist} — ${root.currentTitle}`, "music_note");
    }

    function download(result: var): void {
        if (!result || !result.webpage_url) {
            root.error = Tr.tr("No URL to download");
            return;
        }
        if (root.downloading) {
            Toaster.toast(Tr.tr("Download busy"), Tr.tr("A download is already in progress"), "warning", Toast.Warning);
            return;
        }
        root.downloading = true;
        root.downloadProgress = "0";
        root.downloadTitle = result.title || "";
        sendCmd({
            action: "download",
            url: result.webpage_url,
            title: result.title || "Untitled",
            artist: result.artist || "Unknown"
        });
    }

    function refreshLibrary(): void {
        sendCmd({ action: "library" });
    }

    function checkDeps(): void {
        sendCmd({ action: "check_deps" });
    }

    // ── Queue ("Up next") ─────────────────────────────────────────
    function queueEntryOf(item: var): var {
        if (!item)
            return null;
        if (item.path && !item.webpage_url) {
            return {
                title: item.title || String(item.path).split("/").pop(),
                artist: item.artist || "",
                webpage_url: "",
                thumbnail: "",
                duration: 0,
                path: item.path
            };
        }
        if (!item.webpage_url)
            return null;
        return {
            title: item.title || Tr.tr("Unknown"),
            artist: item.artist || "",
            webpage_url: item.webpage_url,
            thumbnail: item.thumbnail || "",
            duration: item.duration || 0,
            path: ""
        };
    }

    function enqueue(item: var): void {
        const e = queueEntryOf(item);
        if (!e) {
            root.error = Tr.tr("Nothing to queue");
            return;
        }
        queue = queue.concat([e]);
        root.pushMprisState();
        Toaster.toast(Tr.tr("Added to queue"), e.artist ? `${e.artist} — ${e.title}` : e.title, "playlist_add");
    }

    function playEntry(entry: var): void {
        if (!entry)
            return;
        if (entry.path && !entry.webpage_url)
            playLocal(entry.path, entry.title, entry.artist);
        else
            resolveAndPlay(entry);
    }

    function playQueueIndex(index: int): void {
        if (index < 0 || index >= queue.length)
            return;
        const next = queue[index];
        root._advancing = next.webpage_url ? next : null;
        queue = queue.slice(index + 1);
        root.pushMprisState();
        playEntry(next);
    }

    function playNext(): void {
        playQueueIndex(0);
    }

    function playPrevious(): void {
        // No history: restart the current track.
        if (root.currentUrl)
            seekTo(0);
    }

    function removeFromQueue(index: int): void {
        if (index < 0 || index >= queue.length)
            return;
        const next = queue.slice();
        next.splice(index, 1);
        queue = next;
        root.pushMprisState();
    }

    function clearQueue(): void {
        if (queue.length === 0)
            return;
        queue = [];
        root.pushMprisState();
    }

    // ── Playback helpers ──────────────────────────────────────────
    function statusString(): string {
        if (player.playbackState === MediaPlayer.PlayingState)
            return "Playing";
        if (player.playbackState === MediaPlayer.PausedState)
            return "Paused";
        return "Stopped";
    }

    // Publish playback state to the backend MPRIS server so the
    // dashboard media card, lyrics, player selector and media keys work.
    function pushMprisState(): void {
        let lengthUs = root.pendingLengthUs;
        if (player.duration > 0)
            lengthUs = Math.round(player.duration * 1000);
        sendCmd({
            action: "mpris_state",
            status: statusString(),
            title: root.currentTitle,
            artist: root.currentArtist,
            art_url: root.pendingArtUrl,
            url: root.pendingUrl,
            length_us: lengthUs,
            position_us: Math.round(root.playbackPosition * 1000),
            volume: root.volume,
            serial: root.mprisSerial,
            can_next: root.queue.length > 0,
            can_prev: !!root.currentUrl
        });
    }

    // Transport commands arriving from MPRIS clients (dashboard buttons,
    // media keys) via the backend.
    function handleMprisCommand(msg: var): void {
        switch (msg.command) {
        case "toggle":
            if (root.currentUrl)
                togglePlay();
            break;
        case "play":
            if (root.currentUrl && player.playbackState !== MediaPlayer.PlayingState)
                player.play();
            break;
        case "pause":
            if (player.playbackState === MediaPlayer.PlayingState)
                player.pause();
            break;
        case "stop":
            stopPlayback();
            break;
        case "next":
            playNext();
            break;
        case "previous":
            playPrevious();
            break;
        case "seek":
            if (root.currentUrl)
                seekTo(root.playbackPosition + (msg.offset_us || 0) / 1000);
            break;
        case "position":
            if (root.currentUrl)
                seekTo((msg.position_us || 0) / 1000);
            break;
        case "volume":
            setVolume(msg.value ?? root.volume);
            break;
        }
    }

    function togglePlay(): void {
        if (player.playbackState === MediaPlayer.PlayingState)
            player.pause();
        else if (player.playbackState === MediaPlayer.PausedState)
            player.play();
        else if (root.currentUrl)
            player.play();
    }

    function stopPlayback(): void {
        player.stop();
        root.currentUrl = "";
        player.source = "";
        root.isPlaying = false;
        root.isPaused = false;
        root.playbackPosition = 0;
        root.playbackDuration = 0;
        root.pushMprisState();
    }

    function seekTo(pos: real): void {
        player.setPosition(Math.round(pos));
        root.playbackPosition = Math.round(pos);
        root.pushMprisState();
    }

    function setVolume(v: real): void {
        root.volume = CUtils.clamp(v, 0, 1);
        root.pushMprisState();
    }

    // ── Lifecycle ─────────────────────────────────────────────────
    Component.onCompleted: {
        root.ready = true;
        Qt.callLater(checkDeps);
        Qt.callLater(refreshLibrary);
    }

    Component.onDestruction: {
        try {
            player.stop();
        } catch (e) {}
        if (backend.running)
            backend.running = false;
    }
}
