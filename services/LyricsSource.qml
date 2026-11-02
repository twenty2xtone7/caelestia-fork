pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Services
import qs.utils
import "lyrics/Core.js" as Core
import "lyrics/Lrclib.js" as Lrclib
import "lyrics/NetEase.js" as NetEase
import "lyrics/Qq.js" as Qq
import "lyrics/Kugou.js" as Kugou
import "lyrics/Kuwo.js" as Kuwo
import "lyrics/Spicy.js" as Spicy

// Caelestia's QML lyrics source: a drop-in for the compiled `Lyrics` singleton
// that also supports this repo's own providers.
//
// Consumers use the same names either way — lyrics, hasLyrics, loading, offset,
// selectedCandidate, indexForTime(), timeForIndex(), setTrack(), clearTrack() —
// and `preferredBackend` picks the engine behind them:
//
//   "caelestia" — delegate everything to Caelestia's C++ backend (Lyrics).
//   "auto"      — the provider chain below, first acceptable match wins.
//   "lrclib" | "netease" | "qq" | "kugou" | "kuwo" | "spicy" — that one only.
//
// Track feeding is owned by services/Players.qml. Settings and the per-track
// cache share one file: $XDG_STATE_HOME/caelestia/lyrics-provider.json.
Singleton {
    id: root

    // ── Engine selection ──
    property string preferredBackend: "auto"
    // SpicyLyrics' API is Spotify-client-only, so that provider stays off until
    // the user pastes a token. Empty token = provider disabled.
    property string spotifyToken: ""
    property int cacheTtlDays: 14
    // Bump when stored entries stop meaning what they used to.
    readonly property int cacheSchema: 2

    readonly property bool usingCaelestia: root.preferredBackend === "caelestia"
    readonly property bool spicyEnabled: root.spotifyToken.length > 0 && root.spotifyId.length > 0

    // ── Lyrics surface (drop-in for Caelestia's Lyrics singleton) ──
    readonly property var lyrics: root.usingCaelestia ? Lyrics.lyrics : root._lines.map(l => l.text)
    readonly property bool hasLyrics: root.usingCaelestia ? Lyrics.hasLyrics : root._lines.length > 0
    readonly property bool loading: root.usingCaelestia ? Lyrics.loading : root._loading
    readonly property string backend: root.usingCaelestia ? "Caelestia" : root._backendName
    readonly property var selectedCandidate: root.usingCaelestia ? Lyrics.selectedCandidate : root._candidate

    // Sync offset in ms; same meaning as Lyrics.offset.
    property double offset: root.usingCaelestia ? Lyrics.offset : 0
    onOffsetChanged: if (root.usingCaelestia)
        Lyrics.offset = root.offset

    property var _lines: [] // [{ time, text }] sorted by time
    property var _candidate: ({ title: "", artist: "", album: "" })
    property bool _loading: false
    property string _backendName: ""
    property bool synced: true
    property string error: ""

    // ── Track ──
    property string trackArtist: ""
    property string trackTitle: ""
    property string trackAlbum: ""
    property real trackDuration: 0
    property string trackUri: ""

    readonly property string spotifyId: {
        const m = root.trackUri.match(/spotify:track:([A-Za-z0-9]+)/) || root.trackUri.match(/open\.spotify\.com\/track\/([A-Za-z0-9]+)/);
        return m ? m[1] : "";
    }

    signal trackChanged()

    // ── Indexing ──
    function indexForTime(time: real): int {
        if (root.usingCaelestia)
            return Lyrics.indexForTime(time);
        const t = time + root.offset / 1000;
        const ls = root._lines;
        if (!ls.length)
            return -1;
        let lo = 0;
        let hi = ls.length;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (ls[mid].time <= t)
                lo = mid + 1;
            else
                hi = mid;
        }
        return lo - 1;
    }

    function timeForIndex(index: int): real {
        if (root.usingCaelestia)
            return Lyrics.timeForIndex(index);
        return index >= 0 && index < root._lines.length ? root._lines[index].time : -1;
    }

    // ── Feeding ──
    function setTrack(artist: string, title: string, album: string, duration: real, uri: string): void {
        const key = Core.trackKey({ artist: artist, title: title, album: album, duration: duration });
        if (key === root._lastKey)
            return;

        root._stopPending();
        root._lastKey = key;
        root._cacheKey = key;

        root.trackArtist = artist ?? "";
        root.trackTitle = title ?? "";
        root.trackAlbum = album ?? "";
        root.trackDuration = duration ?? 0;
        root.trackUri = uri ?? "";
        root._lines = [];
        root._candidate = ({ title: "", artist: "", album: "" });
        root._backendName = "";
        root.error = "";
        root._loading = false;
        root.trackChanged();

        if (root.usingCaelestia) {
            Lyrics.setTrack(root.trackArtist, root.trackTitle, root.trackAlbum, root.trackDuration);
            return;
        }

        if (!root.trackTitle && !root.trackArtist)
            return;

        const cached = root._cacheGet(key);
        if (cached && cached.lines?.length) {
            root._commit(root._gen, cached.lines, cached.backend, null, true);
            return;
        }

        root._loading = true;
        root._chain = root._providers();
        root._chainIndex = 0;
        root._step(root._gen);
    }

    function clearTrack(): void {
        root._stopPending();
        root._lastKey = "";
        root._cacheKey = "";
        root.trackArtist = "";
        root.trackTitle = "";
        root.trackAlbum = "";
        root.trackDuration = 0;
        root.trackUri = "";
        root._lines = [];
        root._candidate = ({ title: "", artist: "", album: "" });
        root._loading = false;
        root.error = "";
        root._backendName = "";
        if (root.usingCaelestia)
            Lyrics.clearTrack();
        root.trackChanged();
    }

    function refresh(): void {
        root._lastKey = "";
        root.setTrack(root.trackArtist, root.trackTitle, root.trackAlbum, root.trackDuration, root.trackUri);
    }

    // ── Orchestration ──
    property int _gen: 0
    property int _reqId: 0
    property string _lastKey: ""
    property string _cacheKey: ""
    property var _chain: []
    property int _chainIndex: 0
    property var _pendingCb: null
    property var _fallback: null
    property int _spicyGen: -1

    function _stopPending(): void {
        root._gen += 1;
        root._reqId += 1;
        root._pendingCb = null;
        root._fallback = null;
        if (spicyProc.running)
            spicyProc.running = false;
        timeout.stop();
    }

    function _track(): var {
        return { artist: root.trackArtist, title: root.trackTitle, album: root.trackAlbum, duration: root.trackDuration };
    }

    // Stored values from an older build (or a hand edit) must not leave the
    // picker on an engine that does not exist.
    function _knownBackend(name: var): string {
        switch (String(name ?? "")) {
        case "lrclib":
        case "netease":
        case "qq":
        case "kugou":
        case "kuwo":
        case "spicy":
        case "caelestia":
            return String(name);
        }
        return "auto";
    }

    function _providerByName(name: string): var {
        switch (name) {
        case "lrclib":
            return Lrclib;
        case "netease":
            return NetEase;
        case "qq":
            return Qq;
        case "kugou":
            return Kugou;
        case "kuwo":
            return Kuwo;
        case "spicy":
            return root.spicyEnabled ? Spicy : null;
        }
        return null;
    }

    function _providers(): var {
        if (root.preferredBackend !== "auto") {
            const one = root._providerByName(root.preferredBackend);
            return one ? [one] : [];
        }
        const rest = [Lrclib, NetEase, Qq, Kugou, Kuwo];
        return root.spicyEnabled ? [Spicy].concat(rest) : rest;
    }

    function _next(gen: int): void {
        if (gen !== root._gen)
            return;
        root._chainIndex += 1;
        root._step(gen);
    }

    function _step(gen: int): void {
        if (gen !== root._gen)
            return;
        if (root._chainIndex >= root._chain.length) {
            // Nothing timed turned up. Fall back to the untimed result we kept
            // aside rather than reporting no lyrics at all.
            const fallback = root._fallback;
            root._fallback = null;
            if (fallback)
                root._commit(gen, fallback.lines, fallback.backend, fallback.cand, true);
            else
                root._commit(gen, [], "", null, true);
            return;
        }
        const p = root._chain[root._chainIndex];
        if (p === Spicy) {
            root._spicyGen = gen;
            spicyProc.command = Spicy.command(root.spotifyId, root.spotifyToken);
            spicyProc.running = true;
            return;
        }
        root._http(gen, p.searchRequest(root._track()), text => root._onSearch(gen, p, text));
    }

    function _onSearch(gen: int, p: var, text: string): void {
        if (gen !== root._gen)
            return;
        if (text === null) {
            root._next(gen);
            return;
        }
        let cands = [];
        try {
            cands = p.searchCandidates(text);
        } catch (e) {
            cands = [];
        }
        const pick = Core.best(cands, root._track());
        if (!pick) {
            root._next(gen);
            return;
        }
        const c = pick.cand;
        if (c.lrc || c.plain) {
            root._commit(gen, root._linesFor(c.lrc || "", c.plain || ""), p.name, c, false);
            return;
        }
        const lreq = p.lyricRequest(c);
        if (!lreq) {
            root._next(gen);
            return;
        }
        root._http(gen, lreq, t => root._onLyric(gen, p, t, c));
    }

    function _onLyric(gen: int, p: var, text: string, cand: var): void {
        if (gen !== root._gen)
            return;
        if (text === null) {
            root._next(gen);
            return;
        }
        let r = null;
        try {
            r = p.lyricResponse(text);
        } catch (e) {
            r = null;
        }
        if (!r || (!r.lrc && !r.plain)) {
            root._next(gen);
            return;
        }
        root._commit(gen, root._linesFor(r.lrc || "", r.plain || ""), p.name, cand, false);
    }

    function _onSpicy(code: int, text: string): void {
        const gen = root._spicyGen;
        if (gen !== root._gen)
            return;
        let obj = code === 0 ? Spicy.parse(text) : null;
        if (Array.isArray(obj))
            obj = Core.unpackLyrics(obj);
        if (!obj) {
            console.info("[Lyrics] Spicy returned no usable payload, falling through");
            root._next(gen);
            return;
        }
        const r = Core.spicyToLines(obj);
        console.info(`[Lyrics] Spicy payload type=${obj.Type} timed=${r.synced} lines=${r.lines.length}`);
        if (!r.lines.length) {
            root._next(gen);
            return;
        }
        root._commit(gen, Core.creditFilter(r.lines), "Spicy", { title: root.trackTitle, artist: root.trackArtist, album: root.trackAlbum }, false);
    }

    // Render-able lines from a provider's synced/plain text. Timestamps are left
    // as they are: _commit() decides whether an untimed result is worth keeping.
    function _linesFor(lrc: string, plain: string): var {
        const parsed = lrc ? Core.parseLrc(lrc) : [];
        if (parsed.length && parsed.some(l => l.time > 0))
            return parsed;
        const pl = Core.creditFilter(Core.linesFromPlain(plain));
        return pl.length ? pl : parsed;
    }

    function _commit(gen: int, lines: var, be: string, cand: var, final: bool): void {
        if (gen !== root._gen)
            return;
        const timed = !!lines?.length && lines.some(l => l.time > 0);
        // A provider that has the words but not the timings is a last resort:
        // keep walking in case a later one is line-synced.
        if (!final && lines?.length && !timed && root._chainIndex < root._chain.length - 1) {
            root._fallback = { lines: lines, backend: be, cand: cand };
            console.info(`[Lyrics] ${be} → ${lines.length} lines (untimed), still looking`);
            root._next(gen);
            return;
        }
        timeout.stop();
        root._loading = false;
        if (!lines?.length) {
            root._lines = [];
            root._backendName = be;
            root.error = be ? "" : root.preferredBackend === "spicy" ? "A Spotify token is required for Spicy" : "No lyrics found";
            console.info(`[Lyrics] no lyrics (${be || "all providers exhausted"})`);
            return;
        }
        // Untimed lines still need timestamps so indexForTime() tracks the
        // playback position instead of sticking on line 0.
        const out = timed ? lines : Core.synthesizeTimes(lines, root.trackDuration);
        root._lines = out;
        root._backendName = be;
        root.synced = timed;
        root.error = "";
        if (cand)
            root._candidate = cand;
        if (root._cacheKey)
            root._cachePut(root._cacheKey, { v: root.cacheSchema, lines: out, backend: be, synced: timed });
        console.info(`[Lyrics] ${root._backendName || "none"} → ${out.length} lines (${timed ? "synced" : "untimed"})`);
    }

    function _http(gen: int, req: var, cb: var): void {
        root._reqId += 1;
        const id = root._reqId;
        root._pendingCb = cb;
        timeout.restart();
        Requests.get(req.url, body => {
            if (id !== root._reqId)
                return;
            timeout.stop();
            root._pendingCb = null;
            cb(body);
        }, () => {
            if (id !== root._reqId)
                return;
            timeout.stop();
            root._pendingCb = null;
            cb(null);
        }, req.headers ?? {});
    }

    Timer {
        id: timeout

        interval: 8000
        onTriggered: {
            const cb = root._pendingCb;
            root._reqId += 1;
            root._pendingCb = null;
            if (cb)
                cb(null);
        }
    }

    Process {
        id: spicyProc

        stdout: StdioCollector {
            id: spicyOut
        }
        stderr: StdioCollector {
            id: spicyErr
        }
        onExited: code => root._onSpicy(code, spicyOut.text)
    }

    // ── Persistence: settings + per-track cache ──
    property var _data: ({ backend: "auto", token: "", tracks: {} })
    property bool _loaded: false

    // A cache entry from another provider still satisfies an explicit choice
    // only when it came from that provider, so switching backend really switches.
    function _cacheGet(key: string): var {
        const e = root._data.tracks ? root._data.tracks[key] : null;
        if (!e || e.v !== root.cacheSchema)
            return null;
        if (e.saved && Date.now() - e.saved > root.cacheTtlDays * 86400000) {
            delete root._data.tracks[key];
            return null;
        }
        if (root.preferredBackend !== "auto" && String(e.backend ?? "").toLowerCase() !== root.preferredBackend)
            return null;
        return e;
    }

    function _cachePut(key: string, entry: var): void {
        entry.saved = Date.now();
        root._data.tracks[key] = entry;
        saveTimer.restart();
    }

    onSpotifyTokenChanged: {
        if (!root._loaded)
            return;
        root._data.token = root.spotifyToken;
        saveTimer.restart();
    }

    onPreferredBackendChanged: {
        console.info(`[Lyrics] backend -> ${root.preferredBackend}`);
        if (!root._loaded)
            return;
        root._data.backend = root.preferredBackend;
        saveTimer.restart();
        // Hand the current track to whichever engine was just picked.
        if (root.usingCaelestia) {
            root._activateCaelestia();
        } else {
            Lyrics.clearTrack();
            root._lastKey = "";
            if (root.trackTitle || root.trackArtist)
                root.setTrack(root.trackArtist, root.trackTitle, root.trackAlbum, root.trackDuration, root.trackUri);
        }
    }

    // Compiled Lyrics owns the result from here on; drop anything this file
    // fetched before the stored setting was known.
    function _activateCaelestia(): void {
        root._stopPending();
        root._lines = [];
        root._backendName = "";
        root.error = "";
        if (root.trackTitle || root.trackArtist)
            Lyrics.setTrack(root.trackArtist, root.trackTitle, root.trackAlbum, root.trackDuration);
    }

    Timer {
        id: saveTimer

        interval: 800
        // Never write before the file has been read, or the first track's cache
        // save would clobber the stored backend/token with the defaults.
        onTriggered: {
            if (!root._loaded) {
                saveTimer.restart();
                return;
            }
            store.setText(JSON.stringify(root._data));
        }
    }

    FileView {
        id: store

        printErrors: false
        path: `${Paths.state}/lyrics-provider.json`
        // The store writes the file itself, and Quickshell's FileView watches
        // it: our own save echoes back as a load, and its atomic replace
        // (write temp, rename) can even surface as a transient FileNotFound.
        // Re-applying either would push stale or defaulted settings back over
        // the ones in memory — which reset the chosen backend on every track —
        // so only the first read is trusted.
        onLoaded: {
            if (root._loaded)
                return;
            try {
                const d = JSON.parse(text());
                if (d && typeof d === "object")
                    root._data = { backend: root._knownBackend(d.backend), token: d.token ?? "", tracks: d.tracks ?? {} };
            } catch (e) {
                console.warn("LyricsSource: cannot parse lyrics-provider.json:", e);
            }
            console.info(`[Lyrics] loaded settings: backend=${root._data.backend} cached=${Object.keys(root._data.tracks).length}`);
            root.spotifyToken = root._data.token ?? "";
            root.preferredBackend = root._data.backend;
            root._loaded = true;
            if (root.usingCaelestia)
                root._activateCaelestia();
        }
        onLoadFailed: err => {
            if (root._loaded)
                return;
            root._loaded = true;
            // First run: create the file so it is there to edit by hand.
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => store.setText(JSON.stringify(root._data)));
        }
    }

    Process {
        id: mkdirProc

        command: ["mkdir", "-p", Paths.state]
        running: true
    }
}