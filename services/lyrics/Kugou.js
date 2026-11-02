.pragma library

// Kugou Music — keyless search + lyric endpoints.

var name = "Kugou";

var HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Referer": "https://www.kugou.com/"
};

function searchRequest(track) {
    const q = encodeURIComponent(`${track.title} ${track.artist}`);
    return { url: `https://songsearch.kugou.com/song_search_v2?keyword=${q}&page=1&pagesize=10&platform=WebFilter`, headers: HEADERS };
}

function searchCandidates(text) {
    let doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return [];
    }
    const list = doc?.data?.lists;
    if (!Array.isArray(list)) return [];
    return list.map(s => ({
        id: s.FileHash ?? "",
        title: s.SongName ?? "",
        artist: s.SingerName ?? "",
        album: s.AlbumName ?? "",
        duration: Number(s.Duration) || 0
    }));
}

function lyricRequest(cand) {
    if (!cand.id) return null;
    return { url: `https://m.kugou.com/app/i/krc.php?cmd=100&hash=${encodeURIComponent(cand.id)}`, headers: HEADERS };
}

function lyricResponse(text) {
    if (!text || text.charCodeAt(0) !== 91 /* [ */) return null;
    return { lrc: text, plain: "" };
}
