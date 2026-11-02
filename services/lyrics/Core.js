.pragma library

// Pure helpers for the lyrics backend: metadata normalisation, candidate
// scoring and LRC/TTML/Spicy parsing. No QML or network access here so the
// whole file can be exercised by tests/lyrics-core.test.mjs.

var CREDIT_KEYWORDS = [
    "作词", "作曲", "编曲", "制作", "收录", "演奏", "词:", "曲:",
    "Lyricist", "Composer", "Arranger", "Producer", "Mixing", "Mastering",
    "Written by", "Music by", "Lyrics by", "Mixed by", "Mastered by", "label:", "Label:"
];

var VERSION_WORDS = /(?:feat\.?|ft\.?|with|remaster(?:ed)?|remix|live|radio\s*edit|album\s*version|single\s*version|deluxe|explicit|clean|bonus|instrumental|acoustic|demo|mono|stereo|anniversary|re-?recorded|sped\s*up|slowed|nightcore|twin\s*ver|\bver\b)/i;

function decodeEntities(s) {
    return String(s ?? "")
        .replace(/&nbsp;/gi, " ")
        .replace(/&apos;|&#39;/gi, "'")
        .replace(/&quot;|&#34;/gi, "\"")
        .replace(/&lt;/gi, "<")
        .replace(/&gt;/gi, ">")
        .replace(/&amp;/gi, "&")
        .replace(/&#x([0-9a-f]+);/gi, (m, h) => String.fromCharCode(parseInt(h, 16)))
        .replace(/&#(\d+);/g, (m, d) => String.fromCharCode(+d));
}

function normalize(s) {
    return decodeEntities(s)
        .toLowerCase()
        .replace(/\[[^\]]*\]|\([^)]*\)/g, " ")
        .replace(/[^\p{L}\p{N}]+/gu, " ")
        .replace(/\s+/g, " ")
        .trim();
}

// Title with edition/version suffixes and featured credits removed.
function baseTitle(title) {
    let t = decodeEntities(title).replace(/\[[^\]]*\]/g, " ");
    // Titles stack qualifiers ("Song - Twin Ver. (Band) - Sped Up Version"), so
    // peel them off one at a time. Only a qualifier carrying a version keyword
    // is dropped, so real titles containing a dash survive.
    let prev;
    do {
        prev = t;
        t = t.replace(/\s+-\s+([^-]*)$/, (m, tail) => (VERSION_WORDS.test(tail) ? " " : m));
    } while (t !== prev);
    t = t.replace(/\((?:[^()]*)\)/g, (m) => (VERSION_WORDS.test(m) ? " " : m));
    return normalize(t);
}

function primaryArtist(artist) {
    let a = decodeEntities(artist);
    a = a.split(/\s*(?:,|&|;|\/|\bwith\b|\bfeat\.?\b|\bft\.?\b|\bx\b|×)\s*/i)[0] || a;
    return normalize(a);
}

function levenshtein(a, b) {
    const m = a.length;
    const n = b.length;
    if (!m) return n;
    if (!n) return m;
    let prev = new Array(n + 1);
    let cur = new Array(n + 1);
    for (let j = 0; j <= n; j++) prev[j] = j;
    for (let i = 1; i <= m; i++) {
        cur[0] = i;
        for (let j = 1; j <= n; j++) {
            const cost = a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1;
            cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
        }
        const tmp = prev;
        prev = cur;
        cur = tmp;
    }
    return prev[n];
}

function similarity(a, b) {
    if (!a && !b) return 1;
    if (!a || !b) return 0;
    const max = Math.max(a.length, b.length);
    return max === 0 ? 1 : 1 - levenshtein(a, b) / max;
}

var DEFAULT_THRESHOLD = 0.6;
var DURATION_TOLERANCE = 8; // seconds

// Returns a 0..1 score, or -1 when the candidate must not be accepted.
function score(track, cand) {
    const tTitle = baseTitle(track.title);
    const cTitle = baseTitle(cand.title);
    if (!tTitle || !cTitle) return -1;

    const titleSim = similarity(tTitle, cTitle);
    if (titleSim < 0.5) return -1;

    const tArtist = primaryArtist(track.artist);
    const cArtist = primaryArtist(cand.artist);
    const artistSim = tArtist && cArtist ? similarity(tArtist, cArtist) : 0;

    let durationSim = 0;
    const td = Number(track.duration) || 0;
    const cd = Number(cand.duration) || 0;
    if (td > 0 && cd > 0) {
        const delta = Math.abs(td - cd);
        if (delta > DURATION_TOLERANCE) return -1;
        durationSim = 1 - delta / DURATION_TOLERANCE;
    }

    const albumSim = track.album && cand.album ? similarity(normalize(track.album), normalize(cand.album)) : 0;

    let s = titleSim * 0.5 + artistSim * 0.32 + durationSim * 0.13 + albumSim * 0.05;
    if (titleSim === 1) s += 0.05;
    if (tArtist && cArtist && artistSim < 0.34) s -= 0.12;
    return Math.max(-1, Math.min(1, s));
}

// Highest-scoring acceptable candidate, or null.
function best(cands, track, threshold) {
    const limit = threshold ?? DEFAULT_THRESHOLD;
    let bestCand = null;
    let bestScore = -1;
    for (const c of cands ?? []) {
        const s = score(track, c);
        if (s >= limit && s > bestScore) {
            bestScore = s;
            bestCand = c;
        }
    }
    return bestCand ? { cand: bestCand, score: bestScore } : null;
}

var TIME_TAG = /\[(\d+):(\d{1,2}(?:[.:]\d{1,3})?)\]/g;
var WORD_TAG = /<\d+:\d{1,2}(?:[.:]\d{1,3})?>/g;

function tagSeconds(min, sec) {
    return parseInt(min, 10) * 60 + parseFloat(String(sec).replace(":", "."));
}

// LRC / enhanced-LRC. Returns [{ time, text }] sorted by time.
function parseLrc(text) {
    const src = decodeEntities(text);
    const out = [];
    const off = src.match(/\[offset:\s*([+-]?\d+)\s*\]/i);
    const offset = off ? parseInt(off[1], 10) / 1000 : 0;
    const hasTag = /\[\d+:\d{1,2}/.test(src);

    for (const line of src.split(/\r?\n/)) {
        TIME_TAG.lastIndex = 0;
        const stamps = [];
        let m;
        while ((m = TIME_TAG.exec(line)) !== null) stamps.push(tagSeconds(m[1], m[2]));
        if (!stamps.length) continue;
        const txt = line.replace(TIME_TAG, "").replace(WORD_TAG, "").trim();
        for (const t of stamps) out.push({ time: t + offset, text: txt });
    }

    // Plain-text sources that produced no tags at all are not LRC.
    if (!out.length && !hasTag) return [];
    out.sort((a, b) => a.time - b.time);
    return creditFilter(out);
}

function creditFilter(lines) {
    const out = [];
    for (const l of lines) {
        if (l.time < 20) {
            const low = l.text.toLowerCase();
            let isCredit = false;
            for (const k of CREDIT_KEYWORDS) {
                if (low.indexOf(k.toLowerCase()) >= 0) {
                    isCredit = true;
                    break;
                }
            }
            if (isCredit && (l.text.indexOf(":") >= 0 || l.text.length < 25)) continue;
        }
        out.push(l);
    }
    return out;
}

function linesFromPlain(text) {
    const out = [];
    for (const raw of decodeEntities(text).split(/\r?\n/)) {
        const t = raw.trim();
        if (t) out.push({ time: 0, text: t });
    }
    return out;
}

// Unsynced lyrics still need timestamps for indexForTime(); spread them over
// the track (or 4s/line when the duration is unknown).
function synthesizeTimes(lines, duration) {
    const n = lines.length;
    if (!n) return lines;
    const total = Number(duration) > 0 ? Number(duration) : n * 4;
    const step = total / (n + 1);
    return lines.map((l, i) => ({ time: (i + 1) * step, text: l.text }));
}

function parseClock(s) {
    const parts = String(s).trim().split(":").map(Number);
    if (parts.some(isNaN)) return -1;
    if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    if (parts.length === 2) return parts[0] * 60 + parts[1];
    if (parts.length === 1) return parts[0];
    return -1;
}

// Minimal TTML: <p begin="...">…</p>, ignoring nested spans/ttm metadata.
function parseTtml(text) {
    const src = decodeEntities(text);
    const out = [];
    const re = /<p\b[^>]*\bbegin="([^"]+)"[^>]*>([\s\S]*?)<\/p>/gi;
    let m;
    while ((m = re.exec(src)) !== null) {
        const t = m[2].replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim();
        const secs = parseClock(m[1]);
        if (secs >= 0) out.push({ time: secs, text: t });
    }
    out.sort((a, b) => a.time - b.time);
    return creditFilter(out);
}

// SpicyLyrics payload (already unpacked) -> lines. Handles all three types the
// service emits: Syllable (word level), Line, Static (unsynced).
//
// The server separates words with zero-width spaces and swaps lookalike
// characters (Cyrillic о/е/а) to defeat scrapers; the zero-widths are dropped
// here because they would otherwise show up as gaps in the rendered line.
function spicyText(s) {
    return String(s ?? "").replace(/\u200b/g, " ").replace(/\s+/g, " ").trim();
}

function spicyToLines(lyrics) {
    if (!lyrics || typeof lyrics !== "object") return { lines: [], synced: false };
    if (lyrics.Type === "Static" && Array.isArray(lyrics.Lines)) {
        const lines = lyrics.Lines.map(l => ({ time: 0, text: spicyText(typeof l === "string" ? l : l?.Text) })).filter(l => l.text);
        return { lines, synced: false };
    }
    const out = [];
    for (const group of lyrics.Content ?? []) {
        if (group?.Type !== "Vocal") continue;
        if (group.Lead && Array.isArray(group.Lead.Syllables)) {
            let text = "";
            let time = -1;
            for (const s of group.Lead.Syllables) {
                if (time < 0 && typeof s.StartTime === "number") time = s.StartTime / 1000;
                text += (s.IsPartOfWord ? "" : text ? " " : "") + (s.Text ?? "");
            }
            const clean = spicyText(text);
            if (clean) out.push({ time: time < 0 ? 0 : time, text: clean });
        } else if (typeof group.Text === "string") {
            const time = typeof group.StartTime === "number" ? group.StartTime / 1000 : 0;
            const clean = spicyText(group.Text);
            if (clean) out.push({ time, text: clean });
        }
    }
    out.sort((a, b) => a.time - b.time);
    const synced = out.some(l => l.time > 0);
    return { lines: out, synced };
}

// SpicyLyrics ships its lyrics in "SLObjPack": [values, stream], where a stream
// entry is either an index into `values` (>= 0) or a structure opcode. Decoded
// from the wire format; the reference interpreter is AGPL and not used here.
var UNPACK_FORBIDDEN_KEY = /^(?:__proto__|constructor|prototype)$/;

function unpackLyrics(packed) {
    if (!Array.isArray(packed) || packed.length !== 2) return null;
    const values = packed[0];
    const stream = packed[1];
    if (!Array.isArray(values) || !Array.isArray(stream)) return null;

    let cursor = 0;
    const next = () => {
        if (cursor >= stream.length) throw new Error("truncated stream");
        return stream[cursor++];
    };
    const deref = n => {
        if (!Number.isInteger(n) || n < 0 || n >= values.length) throw new Error("bad pointer");
        return values[n];
    };
    const readKey = () => {
        const k = deref(next());
        if (typeof k !== "string" || UNPACK_FORBIDDEN_KEY.test(k)) throw new Error("bad key");
        return k;
    };
    const readNode = () => {
        const op = next();
        if (!Number.isInteger(op)) throw new Error("bad opcode");
        if (op >= 0) return deref(op);
        if (op === -4) return [];
        if (op === -6) return {};
        if (op === -5) return [readNode()];
        if (op === -2) {
            const n = next();
            const arr = [];
            for (let i = 0; i < n; i++) arr.push(readNode());
            return arr;
        }
        if (op === -1) {
            const n = next();
            const keys = [];
            for (let i = 0; i < n; i++) keys.push(readKey());
            const obj = {};
            for (const k of keys) obj[k] = readNode();
            return obj;
        }
        if (op === -3) {
            const n = next();
            const keyCount = next();
            const keys = [];
            for (let i = 0; i < keyCount; i++) keys.push(readKey());
            const arr = [];
            for (let i = 0; i < n; i++) {
                const rec = {};
                for (const k of keys) rec[k] = readNode();
                arr.push(rec);
            }
            return arr;
        }
        throw new Error("unknown opcode " + op);
    };

    try {
        const out = readNode();
        return cursor === stream.length ? out : null;
    } catch (e) {
        return null;
    }
}

// A stable cache key for a track.
function trackKey(track) {
    return `${normalize(track.artist)}|${baseTitle(track.title)}|${Math.round(Number(track.duration) || 0)}`;
}
