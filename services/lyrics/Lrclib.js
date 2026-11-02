.pragma library

// LRCLIB (https://lrclib.net) — community DB, keyless.
// /api/search returns candidates with the lyrics inline, so one request is
// enough: rank with Core.best() and use the winner's synced/plain text.

var name = "LRCLIB";

var UA = "caelestia-shell (https://github.com/caelestia-dots/shell)";

function searchRequest(track) {
    const q = `track_name=${encodeURIComponent(track.title)}&artist_name=${encodeURIComponent(track.artist)}`;
    return { url: `https://lrclib.net/api/search?${q}`, headers: { "User-Agent": UA } };
}

function searchCandidates(text) {
    let arr;
    try {
        arr = JSON.parse(text);
    } catch (e) {
        return [];
    }
    if (!Array.isArray(arr)) return [];
    return arr.map(o => ({
        id: String(o.id ?? ""),
        title: o.trackName ?? "",
        artist: o.artistName ?? "",
        album: o.albumName ?? "",
        duration: Number(o.duration) || 0,
        lrc: o.syncedLyrics ?? "",
        plain: o.plainLyrics ?? ""
    }));
}

function lyricRequest() {
    return null; // lyrics are inline in the search response
}
