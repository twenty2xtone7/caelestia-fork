pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.components.misc
import qs.services
import qs.utils

// cliphist-backed clipboard history. Decode is lazy: image bytes hit
// disk only when a row (or the side preview) actually needs them.
Singleton {
    id: root

    property list<var> entries: []
    property bool loading: false
    property bool open: false
    property bool deleteMode: false

    property int maxPreviews: 50
    property int maxResults: 200
    property int maxQueue: 24
    property var previews: ({})
    property var decodeFailed: ({})
    property var decodeQueue: []
    property bool decoding: false
    property string decodingId: ""
    // Gated by the view: image sources stay empty until shortly after
    // open so texture uploads can't stall view creation.
    property bool imagesReady: false
    property double _openAt: 0
    property double _reloadAt: 0

    readonly property string cacheDir: `${Paths.cache}/clipboard`

    function parseLine(line: string): var {
        const tab = line.indexOf("\t");
        if (tab < 0)
            return null;

        const id = line.slice(0, tab);
        const preview = line.slice(tab + 1);
        const m = preview.match(/\[\[ binary data (\d+) KiB (\w+)(?: (\d+)x(\d+))? \]\]/i);
        const ext = m ? m[2].toLowerCase() : "";
        const isImage = !!(m && ["png", "jpg", "jpeg", "webp", "gif", "bmp", "tif", "tiff"].includes(ext));
        const fileExt = ext === "jpeg" ? "jpg" : ext;

        return {
            id,
            line,
            preview,
            isImage,
            isBinary: preview.startsWith("[[ binary data "),
            mime: isImage ? `image/${fileExt === "jpg" ? "jpeg" : fileExt}` : "text/plain",
            sizeKiB: m ? Number(m[1]) : 0,
            width: m && m[3] ? Number(m[3]) : 0,
            height: m && m[4] ? Number(m[4]) : 0,
            ext: fileExt,
            path: isImage ? `${cacheDir}/${id}.${fileExt}` : ""
        };
    }

    function query(search: string): var {
        const q = (search || "").trim().toLowerCase();
        if (!q)
            return entries.slice(0, root.maxResults);
        return entries.filter(e => e.preview.toLowerCase().includes(q) || e.id.includes(q)).slice(0, root.maxResults);
    }

    function reload(): void {
        // Rapid reopens reuse fresh-enough data instead of spawning
        // `cliphist list` + `find` on every single open.
        if (Date.now() - _reloadAt < 1000)
            return;
        _reloadAt = Date.now();
        // Only flash "Loading…" when there's nothing to show yet;
        // background refreshes swap silently.
        loading = root.entries.length === 0;
        listProc.running = false;
        listProc.running = true;
    }

    function copy(entry: var): void {
        if (!entry?.line)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "clip", entry.line]);
    }

    function remove(entry: var): void {
        if (!entry?.line)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "clip", entry.line]);
        entries = entries.filter(e => e.id !== entry.id);
        Qt.callLater(() => root.reload());
    }

    function ensurePreview(entry: var, highPriority: bool): void {
        if (!entry?.isImage || !entry.path)
            return;
        if (previews[entry.id] || decodeFailed[entry.id] || decodingId === entry.id)
            return;
        const qi = decodeQueue.findIndex(e => e.id === entry.id);
        if (qi >= 0) {
            // Already queued: bump current item to the front so the
            // visible preview doesn't wait behind stale rows.
            if (highPriority && qi > 0) {
                const next = decodeQueue.slice();
                const moved = next.splice(qi, 1);
                next.unshift(moved[0]);
                decodeQueue = next;
            }
            return;
        }
        if (decodeQueue.length >= root.maxQueue) {
            // Drop background thumbnails when scrolling fast; the row
            // re-requests (or jumps the queue) once it becomes current.
            if (!highPriority)
                return;
            decodeQueue = decodeQueue.slice(0, root.maxQueue - 1);
        }
        decodeQueue = highPriority ? [entry].concat(decodeQueue) : decodeQueue.concat([entry]);
        pumpDecode();
    }

    function pumpDecode(): void {
        if (decoding || decodeQueue.length === 0)
            return;
        const entry = decodeQueue[0];
        decodeQueue = decodeQueue.slice(1);
        decoding = true;
        decodingId = entry.id;
        decodeProc.exec(["sh", "-c", "test -s \"$2\" || { mkdir -p \"$3\" && printf '%s\\n' \"$1\" | cliphist decode > \"$2\"; } && test -s \"$2\"", "clip", entry.line, entry.path, cacheDir]);
    }

    function trimPreviews(next: var): void {
        const ids = Object.keys(next).sort((a, b) => (next[a]?.lastAccessed || 0) - (next[b]?.lastAccessed || 0));
        if (ids.length > root.maxPreviews) {
            for (let i = 0; i < ids.length - root.maxPreviews; i++) {
                delete next[ids[i]];
            }
        }
    }

    function markPreview(id: string, path: string): void {
        const next = Object.assign({}, previews);
        next[id] = { path, lastAccessed: Date.now() };
        trimPreviews(next);
        previews = next;
    }

    function markPreviews(paths: var): void {
        const next = Object.assign({}, previews);
        const now = Date.now();
        let changed = false;
        for (const id in paths) {
            if (!next[id]) {
                next[id] = { path: paths[id], lastAccessed: now };
                changed = true;
            }
        }
        if (!changed)
            return;
        trimPreviews(next);
        previews = next;
    }

    function primeCache(): void {
        // One `find` instead of one `test -s` process per image: mark
        // already-decoded files so open/scroll needs zero spawns for them.
        primeProc.exec(["sh", "-c", "find \"$1\" -maxdepth 1 -type f -size +0c -printf '%f\\n' 2>/dev/null", "prime", cacheDir]);
    }

    function markFailed(id: string): void {
        const next = Object.assign({}, decodeFailed);
        next[id] = true;
        decodeFailed = next;
    }

    function toggle(asDelete: bool): void {
        const s = ShellState.forActive();
        if (!s)
            return;

        deleteMode = !!asDelete;

        if (open && s.launcher) {
            if (!asDelete)
                s.launcher = false;
            return;
        }

        open = true;
        _openAt = Date.now();
        // Start the refresh before the view is even built so the
        // subprocess overlaps view creation instead of following it.
        imagesReady = false;
        root.reload();
        if (!s.launcher)
            s.launcher = true;
    }

    Process {
        id: listProc

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (!line)
                        continue;
                    const e = root.parseLine(line);
                    if (e)
                        out.push(e);
                }
                // cliphist is newest-first: same length + same head means
                // nothing changed, so keep the old objects. This avoids a
                // full model/delegate/image rebuild on every open.
                const same = out.length === root.entries.length && (out.length === 0 || out[0].line === root.entries[0].line);
                root.loading = false;
                console.info(`[clip-perf] list+parse ${Date.now() - root._reloadAt}ms, ${out.length} entries${same ? " (unchanged, skipped)" : ""}`);
                if (same)
                    return;
                root.entries = out;
                root.primeCache();
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.loading = false;
        }
    }

    Process {
        id: decodeProc

        onExited: exitCode => {
            const id = root.decodingId;
            const entry = root.entries.find(e => e.id === id);
            if (exitCode === 0 && entry?.path)
                root.markPreview(id, entry.path);
            else if (id)
                root.markFailed(id);
            root.decoding = false;
            root.decodingId = "";
            root.pumpDecode();
        }
    }

    Process {
        id: primeProc

        stdout: StdioCollector {
            onStreamFinished: {
                const byId = {};
                for (const e of root.entries)
                    byId[e.id] = true;
                const found = {};
                const stale = [];
                for (const line of text.split("\n")) {
                    if (!line)
                        continue;
                    const dot = line.lastIndexOf(".");
                    const id = dot > 0 ? line.slice(0, dot) : line;
                    if (byId[id])
                        found[id] = `${root.cacheDir}/${line}`;
                    else
                        stale.push(`${root.cacheDir}/${line}`);
                }
                root.markPreviews(found);
                console.info(`[clip-perf] prime ${Date.now() - root._reloadAt}ms, ${Object.keys(found).length} primed, ${stale.length} stale`);
                // Cache files are pure `cliphist decode` output, so files
                // left behind by deleted entries can be reclaimed safely.
                if (stale.length > 0)
                    Quickshell.execDetached(["rm", "-f", "--"].concat(stale));
            }
        }
    }

    CustomShortcut {
        name: "clipboard"
        description: "Open clipboard picker"
        onPressed: root.toggle(false)
    }

    CustomShortcut {
        name: "clipboardDelete"
        description: "Open clipboard picker (delete)"
        onPressed: root.toggle(true)
    }
}
