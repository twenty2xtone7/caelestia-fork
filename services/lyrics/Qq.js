.pragma library

// QQ Music — keyless search + lyric endpoints (both require a y.qq.com
// referer).

var name = "QQ";

var HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Referer": "https://y.qq.com/"
};

function searchRequest(track) {
    const q = encodeURIComponent(`${track.title} ${track.artist}`);
    return { url: `https://c.y.qq.com/soso/fcgi-bin/client_search_cp?p=1&n=10&w=${q}&format=json`, headers: HEADERS };
}

function searchCandidates(text) {
    let doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return [];
    }
    const list = doc?.data?.song?.list;
    if (!Array.isArray(list)) return [];
    return list.map(s => ({
        id: s.songmid ?? "",
        title: s.songname ?? "",
        artist: (s.singer ?? []).map(a => a.name).join(", "),
        album: s.albumname ?? "",
        duration: Number(s.interval) || 0
    }));
}

function lyricRequest(cand) {
    const mid = encodeURIComponent(cand.id);
    return {
        url: `https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=${mid}&format=json&nobase64=1&g_tk=5381`,
        headers: HEADERS
    };
}

function lyricResponse(text) {
    let doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return null;
    }
    return { lrc: doc?.lyric ?? "", plain: "" };
}
