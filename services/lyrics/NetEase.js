.pragma library

// NetEase Cloud Music — keyless search + lyric endpoints.
// lyric returns lrc (line synced), yrc (word synced, when present) and tlyric
// (translation).

var name = "NetEase";

var HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Referer": "https://music.163.com/"
};

function searchRequest(track) {
    const q = encodeURIComponent(`${track.title} ${track.artist}`);
    return { url: `https://music.163.com/api/search/get?s=${q}&type=1&limit=10`, headers: HEADERS };
}

function searchCandidates(text) {
    let doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return [];
    }
    const songs = doc?.result?.songs;
    if (!Array.isArray(songs)) return [];
    return songs.map(s => ({
        id: String(s.id ?? ""),
        title: s.name ?? "",
        artist: (s.artists ?? []).map(a => a.name).join(", "),
        album: s.album?.name ?? "",
        duration: (Number(s.duration) || 0) / 1000
    }));
}

function lyricRequest(cand) {
    return { url: `https://music.163.com/api/song/lyric?id=${encodeURIComponent(cand.id)}&lv=1&kv=1&tv=-1`, headers: HEADERS };
}

function lyricResponse(text) {
    let doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return null;
    }
    // yrc is word-level but uses its own "[start,duration](...)" format, not
    // LRC, and Dyn-Lyrics is line level — lrc is the one to use.
    return { lrc: doc?.lrc?.lyric || "", plain: "" };
}
