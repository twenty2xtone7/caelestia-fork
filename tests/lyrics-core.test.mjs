// Self-contained checks for services/lyrics/Core.js. No test framework: run
// with `node tests/lyrics-core.test.mjs` (or bun) and it exits non-zero on the
// first failed assertion.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "lyrics", "Core.js"), "utf8").replace(/^\.pragma library\s*$/m, "");

const expose = [
    "decodeEntities", "normalize", "baseTitle", "primaryArtist", "similarity",
    "score", "best", "parseLrc", "linesFromPlain", "synthesizeTimes",
    "parseClock", "parseTtml", "spicyToLines", "unpackLyrics", "trackKey", "creditFilter"
];
const Core = new Function(`${src}\nreturn {${expose.join(",")}};`)();

let passed = 0;
function ok(cond, label) {
    if (!cond) throw new Error(`FAIL: ${label}`);
    passed++;
}
function eq(actual, expected, label) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a !== e) throw new Error(`FAIL: ${label}\n  actual:   ${a}\n  expected: ${e}`);
    passed++;
}

// ── normalisation ───────────────────────────────────────────────────────────
eq(Core.normalize("Radiohead"), "radiohead", "normalize lowercases");
eq(Core.normalize("Creep (Explicit)"), "creep", "normalize strips parenthetical");
eq(Core.decodeEntities("Nice&nbsp;Dream &amp; Co &#39;x&#39;"), "Nice Dream & Co 'x'", "decodeEntities");
eq(Core.baseTitle("Creep - Remastered 2011"), "creep", "baseTitle drops version suffix");
eq(Core.baseTitle("Song - Part II"), "song part ii", "baseTitle keeps real dash suffix");
eq(Core.baseTitle("Cupid - Twin Ver. (FIFTY FIFTY) - Sped Up Version"), "cupid", "baseTitle peels stacked qualifiers");
eq(Core.baseTitle("Cupid (Twin Ver.)"), "cupid", "baseTitle drops version parenthetical");
eq(Core.baseTitle("Bohemian Rhapsody - Remastered 2011"), "bohemian rhapsody", "baseTitle drops trailing remaster");
eq(Core.primaryArtist("Radiohead feat. Someone"), "radiohead", "primaryArtist takes first");
eq(Core.primaryArtist("A & B"), "a", "primaryArtist splits on &");

// ── scoring ─────────────────────────────────────────────────────────────────
const track = { artist: "Radiohead", title: "Creep", album: "Pablo Honey", duration: 238 };
const good = { title: "Creep", artist: "Radiohead", album: "Pablo Honey", duration: 238 };
const okPick = Core.best([good], track);
ok(okPick && okPick.score > 0.9, "best accepts exact match");

// Must-reject cases.
eq(Core.score(track, { title: "Karma Police", artist: "Radiohead", album: "OK Computer", duration: 237 }), -1, "rejects different title");
eq(Core.score(track, { title: "Creep", artist: "Radiohead", album: "x", duration: 350 }), -1, "rejects duration far off");
eq(Core.best([{ title: "Karma Police", artist: "Radiohead", duration: 237 }], track), null, "best returns null when nothing matches");

// A competing wrong-artist result must lose to the right one.
const pick = Core.best([
    { title: "Creep", artist: "Stone Temple Pilots", album: "Core", duration: 238 },
    good
], track);
ok(pick && pick.cand.artist === "Radiohead", "best prefers the matching artist");

// ── LRC ─────────────────────────────────────────────────────────────────────
const lrc = "[00:12.50]Hello\n[00:15.00]World\n[00:02.00]作词: Someone\n";
const lines = Core.parseLrc(lrc);
eq(lines.map(l => l.time), [12.5, 15], "parseLrc reads times and drops credits");
eq(lines.map(l => l.text), ["Hello", "World"], "parseLrc reads text");
eq(Core.parseLrc("just plain text\nno tags"), [], "parseLrc rejects untagged text");

const multi = Core.parseLrc("[00:01.00][00:05.00]Repeated");
eq(multi.length, 2, "parseLrc expands multiple timestamps");
eq(Core.parseLrc("[offset:500]\n[00:01.00]x")[0].time, 1.5, "parseLrc honours offset");

// ── plain / synthesis ───────────────────────────────────────────────────────
eq(Core.linesFromPlain("a\n\n  b  \n").map(l => l.text), ["a", "b"], "linesFromPlain trims and drops blanks");
const synth = Core.synthesizeTimes([{ text: "a" }, { text: "b" }], 100);
ok(synth[0].time > 0 && synth[0].time < synth[1].time && synth[1].time < 100, "synthesizeTimes spreads over duration");

// ── TTML ────────────────────────────────────────────────────────────────────
const ttml = '<tt><body><div><p begin="00:01.500">Line <span>one</span></p><p begin="00:03">Line two</p></div></body></tt>';
eq(Core.parseTtml(ttml).map(l => l.text), ["Line one", "Line two"], "parseTtml flattens spans");
eq(Core.parseClock("01:02:03"), 3723, "parseClock hh:mm:ss");
eq(Core.parseClock("01:02.5"), 62.5, "parseClock mm:ss");

// ── Spicy payloads ──────────────────────────────────────────────────────────
const syllable = {
    Type: "Syllable",
    Content: [{ Type: "Vocal", Lead: { Syllables: [
        { Text: "Hel", StartTime: 1000, IsPartOfWord: false },
        { Text: "lo", StartTime: 1200, IsPartOfWord: true }
    ] } }]
};
const s = Core.spicyToLines(syllable);
eq(s.lines.map(l => l.text), ["Hello"], "spicyToLines joins syllables");
eq(s.synced, true, "spicyToLines marks synced");
eq(Core.spicyToLines({ Type: "Static", Lines: [{ Text: "a" }, { Text: " b " }] }).lines.map(l => l.text), ["a", "b"], "spicyToLines reads Static");
eq(Core.spicyToLines({ Type: "Static", Lines: ["one", "two\u200b words"] }).lines.map(l => l.text), ["one", "two words"], "spicyToLines reads Static string lines and strips zero-width spaces");
eq(Core.spicyToLines(null).lines, [], "spicyToLines tolerates null");

// ── SLObjPack ───────────────────────────────────────────────────────────────
// [values, stream]: -1 object, -2 array, -3 schema array, -4 [], -5 [x], -6 {}.
eq(Core.unpackLyrics([["Type", "Static", "Lines", "hi", "bye"], [-1, 2, 0, 2, 1, -2, 2, 3, 4]]), { Type: "Static", Lines: ["hi", "bye"] }, "unpackLyrics decodes an object with an array");
eq(Core.unpackLyrics([["a", 1, 2], [-3, 2, 1, 0, 1, 2]]), [{ a: 1 }, { a: 2 }], "unpackLyrics decodes a schema array");
eq(Core.unpackLyrics([["x"], [-6]]), {}, "unpackLyrics decodes an empty object");
eq(Core.unpackLyrics([["x"], [-4]]), [], "unpackLyrics decodes an empty array");
eq(Core.unpackLyrics([["x"], [-5, 0]]), ["x"], "unpackLyrics decodes a single-item array");
eq(Core.unpackLyrics([["x"], [0]]), "x", "unpackLyrics decodes a bare primitive");
eq(Core.unpackLyrics([["x"], [0, 0]]), null, "unpackLyrics rejects trailing stream data");
eq(Core.unpackLyrics([["x"], [-2, 1]]), null, "unpackLyrics rejects a truncated stream");
eq(Core.unpackLyrics([["x"], [7]]), null, "unpackLyrics rejects an out-of-range pointer");
eq(Core.unpackLyrics("not packed"), null, "unpackLyrics rejects non-array input");

// ── cache key ───────────────────────────────────────────────────────────────
eq(Core.trackKey(track), Core.trackKey({ ...track, album: "whatever" }), "trackKey ignores album");
ok(Core.trackKey(track) !== Core.trackKey({ ...track, duration: 300 }), "trackKey separates durations");

console.log(`ok - ${passed} assertions`);
