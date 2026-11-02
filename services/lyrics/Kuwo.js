.pragma library

// Kuwo — keyless legacy search + the public songinfoandlrc endpoint.
// Kuwo is unreliable (its API frequently answers "request is illegal" or 301
// depending on region/cookie), so this provider is best effort only and is
// simply skipped when either step fails.

var name = "Kuwo";

var HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Referer": "https://www.kuwo.cn/"
};

function searchRequest(track) {
    const q = encodeURIComponent(`${track.title} ${track.artist}`);
    return {
        url: `https://search.kuwo.cn/r.s?all=${q}&ft=music&itemset=web_2013&client=kt&pn=0&rn=10&rformat=json&encoding=utf8`,
        headers: HEADERS
    };
}

// The legacy endpoint answers with single-quoted pseudo-JSON, so pull fields
// out directly rather than parsing it.
function pick(record, key) {
    const m = record.match(new RegExp(`'${key}':'([^']*)'`));
    return m ? m[1] : "";
}

function searchCandidates(text) {
    if (!text || text.indexOf("abslist") < 0) return [];
    const out = [];
    const re = /\{[^{}]*'MUSICRID':'[^']*'[^{}]*\}/g;
    let m;
    while ((m = re.exec(text)) !== null) {
        const id = pick(m[0], "MUSICRID").replace(/^MUSIC_/, "");
        if (!id) continue;
        out.push({
            id,
            title: pick(m[0], "NAME"),
            artist: pick(m[0], "ARTIST"),
            album: pick(m[0], "ALBUM"),
            duration: Number(pick(m[0], "DURATION")) || 0
        });
    }
    return out;
}

function lyricRequest(cand) {
    if (!cand.id) return null;
    return { url: `https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=${encodeURIComponent(cand.id)}&httpsStatus=1`, headers: HEADERS };
}

function lyricResponse(text) {
    let doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return null;
    }
    const list = doc?.data?.lrclist;
    if (!Array.isArray(list)) return null;
    // [{ time: "12.34", lineLyric: "..." }]
    const lrc = list
        .map(l => {
            const t = parseFloat(l?.time);
            const mins = Math.floor(t / 60);
            const secs = (t - mins * 60).toFixed(2);
            return `[${String(mins).padStart(2, "0")}:${String(secs).padStart(5, "0")}]${l?.lineLyric ?? ""}`;
        })
        .join("\n");
    return { lrc, plain: "" };
}
