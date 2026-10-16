pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.I18n
import qs.utils

// Translation backend for the launcher translate mini-app.
//
// Architecture is a cyclable provider chain:
//
//   TranslateService.translate()
//       ├── "mymemory" (MyMemory, keyless, rate-limited)
//       ├── "google"   (Google gtx endpoint, keyless)
//       └── "offline"  (built-in phrasebook, no network)
//
// `providerId` picks the engine; `cycleProvider()` rotates through
// `providers` and the choice persists to the state dir. Remote engines fall
// back to the local phrasebook on failure so the UI stays useful offline.
// The offline engine only covers the common greetings in phrasebook.json —
// arbitrary vocabulary needs a network engine. Within its resources it is
// dynamic: exact phrases first, then regex patterns ($n slots filled with
// word-translated captures), then word-by-word composition (unknown words
// pass through; zero hits is an explicit miss, never fake success).
//
// No API keys are stored anywhere: the remote providers need none.
// To add a backend later, append a `{ id, name }` entry to `providers` and
// a branch in `translate()` without touching the UI.
//
// Requests are race-safe: every translate() call mints a generation id, and
// completion is announced via finished(generation, result, error) only after
// result/error are final. Stale generations are dropped, never applied.
// History is bounded (`maxHistory`) and persisted to the state dir; it can
// be cleared from the UI.
Singleton {
    id: root

    // Language abstraction: `{ code, name }`, plus optional `aliases` —
    // alternate spellings users may type (e.g. "farsi" or "iran" for
    // Persian). `code` is ISO-639-1, `"auto"` is only valid as a source
    // and means provider-side detection. Remote engines (MyMemory, Google)
    // accept any code here; the offline phrasebook only covers a subset
    // and misses gracefully on the rest.
    readonly property list<var> languages: [
        { code: "auto", name: Tr.tr("Auto Detect") },
        { code: "en", name: Tr.tr("English") },
        { code: "id", name: Tr.tr("Indonesian") },
        { code: "fa", name: Tr.tr("Persian"), aliases: ["farsi", "iran", "iranian"] },
        { code: "ja", name: Tr.tr("Japanese") },
        { code: "ko", name: Tr.tr("Korean") },
        { code: "zh", name: Tr.tr("Chinese") },
        { code: "es", name: Tr.tr("Spanish") },
        { code: "fr", name: Tr.tr("French") },
        { code: "de", name: Tr.tr("German") },
        { code: "pt", name: Tr.tr("Portuguese") },
        { code: "ru", name: Tr.tr("Russian") },
        { code: "ar", name: Tr.tr("Arabic") },
        { code: "hi", name: Tr.tr("Hindi") },
        { code: "nl", name: Tr.tr("Dutch") },
        { code: "it", name: Tr.tr("Italian") },
        { code: "tr", name: Tr.tr("Turkish") },
        { code: "uk", name: Tr.tr("Ukrainian") },
        { code: "vi", name: Tr.tr("Vietnamese") },
        { code: "th", name: Tr.tr("Thai") },
        { code: "ms", name: Tr.tr("Malay") },
        { code: "tl", name: Tr.tr("Filipino"), aliases: ["tagalog"] },
        { code: "pl", name: Tr.tr("Polish") },
        { code: "sv", name: Tr.tr("Swedish") },
        { code: "da", name: Tr.tr("Danish") },
        { code: "fi", name: Tr.tr("Finnish") },
        { code: "no", name: Tr.tr("Norwegian") },
        { code: "cs", name: Tr.tr("Czech") },
        { code: "ro", name: Tr.tr("Romanian") },
        { code: "hu", name: Tr.tr("Hungarian") },
        { code: "el", name: Tr.tr("Greek") },
        { code: "he", name: Tr.tr("Hebrew") },
        { code: "bn", name: Tr.tr("Bengali") },
        { code: "ur", name: Tr.tr("Urdu") },
        { code: "sw", name: Tr.tr("Swahili") }
    ]

    // Resolve a user-typed language ("fa", "persian", "farsi", "iran") to
    // its code. Returns "" when nothing matches.
    function resolveLanguage(query: string): string {
        const q = (query ?? "").trim().toLowerCase();
        if (!q)
            return "";
        for (const l of languages) {
            if (l.code === q)
                return l.code;
        }
        for (const l of languages) {
            if (l.code === "auto")
                continue;
            if (l.name.toLowerCase() === q)
                return l.code;
            for (const a of (l.aliases ?? [])) {
                if (a.toLowerCase() === q)
                    return l.code;
            }
        }
        return "";
    }

    property string sourceCode: "auto"
    property string targetCode: "en"

    // Cyclable engines. `id` is persisted; `name` is shown in the UI.
    readonly property list<var> providers: [
        { id: "mymemory", name: Tr.tr("MyMemory") },
        { id: "google", name: Tr.tr("Google") },
        { id: "offline", name: Tr.tr("Offline") }
    ]
    property string providerId: "mymemory"
    readonly property string providerName: {
        const p = providers.find(p => p.id === providerId);
        return p ? p.name : providerId;
    }

    function cycleProvider(): void {
        const idx = providers.findIndex(p => p.id === providerId);
        providerId = providers[(idx + 1) % providers.length].id;
        error = "";
        // Retranslate immediately so the engine switch is visible.
        if (input.trim() && result)
            translate();
    }

    property string input: ""
    property string result: ""
    property string detectedSource: ""
    property bool translating: false
    property string error: ""

    property list<var> history: []
    readonly property int maxHistory: 20

    readonly property string sourceName: languageName(sourceCode)
    readonly property string targetName: languageName(targetCode)

    property int _generation: 0

    // Client-side timeout for remote engines: MyMemory occasionally stalls
    // instead of failing, which used to leave the UI spinning forever.
    // On timeout the in-flight generation is invalidated (a late response
    // is then dropped as stale) and the offline phrasebook answers
    // immediately with a timeout note.
    property int _timeoutGen: -1
    property string _timeoutText: ""
    property string _timeoutSource: ""
    property string _timeoutTarget: ""
    readonly property int remoteTimeoutMs: 8000

    Timer {
        id: remoteTimeout

        interval: root.remoteTimeoutMs
        onTriggered: root.onRemoteTimeout()
    }

    function armTimeout(text: string, source: string, target: string, generation: int): void {
        _timeoutText = text;
        _timeoutSource = source;
        _timeoutTarget = target;
        _timeoutGen = generation;
        remoteTimeout.restart();
    }

    function onRemoteTimeout(): void {
        if (!translating || _timeoutGen !== _generation)
            return;
        const generation = ++_generation;
        console.info(`[Translate] Request #${_timeoutGen} timed out after ${remoteTimeoutMs}ms, falling back offline`);
        translateLocal(_timeoutText, _timeoutSource, _timeoutTarget, generation, Tr.tr("Service timed out — offline result"));
    }

    // The id of the most recently started request. Readers capture the value
    // returned by translate() and match it in onFinished; older generations
    // are stale by definition.
    readonly property int currentRequestId: _generation

    // Emitted exactly once per request, AFTER result/error are final.
    // Never fires early: complete() is the only emitter and it runs after
    // all state writes for that generation.
    signal finished(int generation, string result, string error)

    function languageName(code: string): string {
        const lang = languages.find(l => l.code === code);
        return lang ? lang.name : code;
    }

    // Split "<text> > <language>" into text + resolved target code.
    // Returns { text, target }: target is "" when there is no `>` suffix
    // or the language is unknown (callers decide: error vs. keep text).
    function splitTargetSuffix(raw: string): var {
        const m = (raw ?? "").match(/^(.*?)\s*>\s*([A-Za-z][A-Za-z ]*?)\s*$/);
        if (!m || !m[1].trim())
            return { text: (raw ?? "").trim(), target: "" };
        return { text: m[1].trim(), target: resolveLanguage(m[2]) };
    }

    function cycleSource(): void {
        const idx = languages.findIndex(l => l.code === sourceCode);
        sourceCode = languages[(idx + 1) % languages.length].code;
        error = "";
    }

    function cycleTarget(): void {
        const targets = languages.filter(l => l.code !== "auto");
        const idx = targets.findIndex(l => l.code === targetCode);
        targetCode = targets[(idx + 1) % targets.length].code;
        error = "";
    }

    function swap(): void {
        // "auto" cannot be a target; fall back to English on that side.
        const newSource = targetCode;
        const newTarget = sourceCode === "auto" ? "en" : sourceCode;
        sourceCode = newSource;
        targetCode = newTarget;
        error = "";

        // Keep the conversation flowing: translate the previous result back.
        if (result) {
            input = result;
            result = "";
            translate();
        }
    }

    function clear(): void {
        input = "";
        result = "";
        detectedSource = "";
        error = "";
    }

    function copyResult(): void {
        if (result)
            Quickshell.execDetached(["wl-copy", result]);
    }

    function clearHistory(): void {
        history = [];
        persistHistory();
    }

    function pushHistory(source: string, translated: string): void {
        const entry = {
            input: source,
            output: translated,
            from: sourceCode,
            to: targetCode,
            detected: detectedSource,
            time: Date.now()
        };
        const next = [entry, ...history.filter(h => !(h.input === source && h.output === translated))];
        history = next.slice(0, maxHistory);
        persistHistory();
    }

    // Instant path: an identical recent translation (same text, same
    // direction) answers immediately without touching the network.
    function lookupCache(text: string): var {
        for (const h of history) {
            if (h.input === text && h.from === sourceCode && h.to === targetCode)
                return h;
        }
        return null;
    }

    // Request-aware translation. Every call mints a new generation id and
    // supersedes any in-flight request; stale callbacks check their
    // generation and drop themselves. Completion is announced via
    // finished(generation, result, error) AFTER result/error are final, so
    // readers never see half-written state. Returns the request id.
    function translate(): int {
        const text = input.trim();
        if (!text) {
            error = Tr.tr("Type something to translate");
            return _generation;
        }

        const generation = ++_generation;
        console.info(`[Translate] Request #${generation} started text="${text}" target="${targetCode}" provider="${providerId}"`);
        translating = true;
        error = "";
        result = ""; // clear stale result at request start, never on finish
        detectedSource = "";

        // Same-language fast path: nothing to do.
        if (sourceCode === targetCode) {
            result = text;
            complete(generation);
            return generation;
        }

        // Cache fast path: repeat of a recent translation, no network.
        const cached = lookupCache(text);
        if (cached) {
            result = cached.output;
            detectedSource = cached.detected || "";
            error = "";
            complete(generation);
            return generation;
        }

        if (providerId === "offline") {
            translateLocal(text, sourceCode, targetCode, generation, "");
        } else if (providerId === "google") {
            requestGoogle(text, sourceCode, targetCode, generation);
        } else {
            requestRemote(text, sourceCode, targetCode, generation);
        }
        return generation;
    }

    // Final step of every completion path: state is already final, so flip
    // the flag and announce. A stale generation never reaches the emit.
    function complete(generation: int): void {
        if (generation !== root._generation) {
            console.info(`[Translate] Request #${generation} ignored: stale request`);
            return;
        }
        remoteTimeout.stop();
        root.translating = false;
        console.info(`[Translate] Request #${generation} accepted result="${root.result}" error="${root.error}"`);
        finished(generation, root.result, root.error);
    }

    // RemoteProvider: MyMemory (https://mymemory.translated.net). Keyless
    // GET endpoint, anonymous quota (~5k chars/day). Failures fall back to
    // the local phrasebook so the UI stays useful offline.
    function requestRemote(text: string, source: string, target: string, generation: int): void {
        const pair = `${source === "auto" ? "autodetect" : source}|${target}`;
        const url = `https://api.mymemory.translated.net/get?q=${encodeURIComponent(text)}&langpair=${pair}`;

        armTimeout(text, source, target, generation);
        Requests.get(url, (responseText, metadata) => {
            if (generation !== root._generation) {
                console.info(`[Translate] Request #${generation} ignored: stale request`);
                return; // stale response
            }

            let translated = "";
            let detected = "";
            try {
                const json = JSON.parse(responseText);
                translated = (json?.responseData?.translatedText ?? "").trim();
                detected = json?.responseData?.detectedLanguage ?? "";
                const status = json?.responseStatus;
                if (status && status !== 200 && status !== "200") {
                    root.translateLocal(text, source, target, generation, Tr.tr("Translation failed (status %1)").arg(status));
                    return;
                }
                if (!translated) {
                    root.translateLocal(text, source, target, generation, Tr.tr("Empty response from service"));
                    return;
                }
                // MyMemory echoes detectable garbage for some inputs; the
                // local phrasebook wins when it has an exact offline match
                // and the remote answer looks like an error string.
                if (/MYMEMORY WARNING|INVALID/i.test(translated)) {
                    root.translateLocal(text, source, target, generation, "");
                    return;
                }
            } catch (e) {
                root.translateLocal(text, source, target, generation, Tr.tr("Invalid response from service"));
                return;
            }

            // State is fully written BEFORE complete(): no reader can observe
            // a cleared flag with a half-written result.
            root.result = translated;
            // `detectedLanguage` can be "id" or "id-ID" style; normalise it.
            const detectedCode = (detected || "").split(/[-_]/)[0].toLowerCase();
            root.detectedSource = detectedCode && source === "auto" ? languageName(detectedCode) : "";
            root.error = "";
            root.pushHistory(text, translated);
            root.complete(generation);
        }, () => {
            if (generation !== root._generation) {
                console.info(`[Translate] Request #${generation} ignored: stale request`);
                return;
            }
            root.translateLocal(text, source, target, generation, Tr.tr("Network request failed"));
        });
    }

    // GoogleProvider: keyless gtx endpoint. Same contract as MyMemory:
    // failures fall back to the local phrasebook.
    function requestGoogle(text: string, source: string, target: string, generation: int): void {
        const url = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=${source}&tl=${target}&dt=t&q=${encodeURIComponent(text)}`;

        armTimeout(text, source, target, generation);
        Requests.get(url, (responseText, metadata) => {
            if (generation !== root._generation) {
                console.info(`[Translate] Request #${generation} ignored: stale request`);
                return; // stale response
            }

            let translated = "";
            let detected = "";
            try {
                // Shape: [[["translated","original",...],...],null,"en",...]
                const json = JSON.parse(responseText);
                const sentences = json?.[0];
                if (Array.isArray(sentences))
                    translated = sentences.map(s => s?.[0] ?? "").join("").trim();
                detected = json?.[2] ?? "";
                if (!translated) {
                    root.translateLocal(text, source, target, generation, Tr.tr("Empty response from service"));
                    return;
                }
            } catch (e) {
                root.translateLocal(text, source, target, generation, Tr.tr("Invalid response from service"));
                return;
            }

            root.result = translated;
            // `json[2]` is normally a code like "en"; ignore garbage so a
            // malformed payload can't surface as a fake detection.
            const detectedStr = String(detected || "");
            const detectedCode = /^[a-z]{2,3}([-_][a-z]+)?$/i.test(detectedStr) ? detectedStr.split(/[-_]/)[0].toLowerCase() : "";
            root.detectedSource = detectedCode && source === "auto" ? languageName(detectedCode) : "";
            root.error = "";
            root.pushHistory(text, translated);
            root.complete(generation);
        }, () => {
            if (generation !== root._generation) {
                console.info(`[Translate] Request #${generation} ignored: stale request`);
                return;
            }
            root.translateLocal(text, source, target, generation, Tr.tr("Network request failed"));
        });
    }

    // LocalProvider: offline phrasebook covering common greetings for every
    // advertised language, both directions. Used when the network fails, when
    // the user selects the offline engine, and as a deterministic fallback
    // for tests. Extend per-language tables here as needed.
    // Offline phrasebook, loaded from phrasebook.json next to this file.
    // Format: { "source|target": { "lowercase phrase": "translation" } }.
    // A "words" section holds per-pair word dictionaries for dynamic
    // composition; single-word phrase pairs are also auto-derived as words.
    // Edit the JSON and restart the shell to apply changes. If the file is
    // missing or invalid, the offline engine simply misses (with an error).
    property var _phrasebook: ({})

    // Built from _phrasebook after load: { "source|target": { word: word } }.
    // Explicit "words" entries win; single-word phrase pairs fill the gaps.
    property var _wordmaps: ({})

    function buildWordMaps(): void {
        const maps = {};
        const explicit = (_phrasebook.words && typeof _phrasebook.words === "object") ? _phrasebook.words : {};
        for (const key of Object.keys(_phrasebook)) {
            if (key === "words" || !key.includes("|"))
                continue;
            const m = Object.assign({}, explicit[key] ?? {});
            const table = _phrasebook[key];
            for (const k of Object.keys(table)) {
                if (/\s/.test(k))
                    continue;
                const v = table[k];
                // Single-word keys are word units; their (possibly
                // multi-word) value is that word's translation.
                if (typeof v !== "string")
                    continue;
                const lk = k.toLowerCase();
                if (m[lk] === undefined)
                    m[lk] = v;
            }
            maps[key] = m;
        }
        for (const key of Object.keys(explicit)) {
            if (key.includes("|") && maps[key] === undefined)
                maps[key] = Object.assign({}, explicit[key]);
        }
        root._wordmaps = maps;
    }

    // Word characters: anything but whitespace and common punctuation, so
    // lookups see "morning" inside "morning,". Kept as a literal in both
    // helpers below — they must stay identical.
    function wordTokens(text) {
        const toks = [];
        const re = /([^\s.,!?;:"'“”‘’()\[\]{}…—–-]+)/g;
        let m;
        while ((m = re.exec(text)) !== null)
            toks.push(m[1]);
        return toks;
    }

    function matchCase(src, dst) {
        if (!dst)
            return dst;
        if (src.length > 1 && src === src.toUpperCase())
            return dst.toUpperCase();
        if (src[0] === src[0].toUpperCase())
            return dst[0].toUpperCase() + dst.slice(1);
        return dst;
    }

    function countHits(text, map) {
        let hits = 0;
        for (const w of root.wordTokens(text)) {
            if (map[w.toLowerCase()] !== undefined)
                hits++;
        }
        return hits;
    }

    function applyWordMap(text, map) {
        let translated = 0;
        let total = 0;
        const out = text.replace(/([^\s.,!?;:"'“”‘’()\[\]{}…—–-]+)/g, tok => {
            total++;
            const hit = map[tok.toLowerCase()];
            if (hit === undefined)
                return tok; // unknown words pass through visibly
            translated++;
            return root.matchCase(tok, hit);
        });
        return { text: out.replace(/\s+/g, " ").trim(), translated: translated, total: total };
    }

    // Regex patterns: {"pattern": "...", "result": "..."}.
    // Patterns are full-matched against the trimmed input (case-insensitive;
    // anchored automatically, so write them without ^$). $n in result is
    // replaced with capture group n, word-translated (literals untouched).
    // $$ is a literal dollar. Invalid regexes are skipped with a warning at
    // load. First matching pattern wins; returns null when nothing matches.
    property var _patterns: ({})

    function buildPatterns(): void {
        const out = {};
        const pats = (_phrasebook.patterns && typeof _phrasebook.patterns === "object") ? _phrasebook.patterns : {};
        for (const key of Object.keys(pats)) {
            if (!key.includes("|"))
                continue;
            const list = pats[key];
            if (!Array.isArray(list))
                continue;
            const arr = [];
            for (const p of list) {
                if (!p || typeof p.pattern !== "string" || typeof p.result !== "string")
                    continue;
                try {
                    arr.push({ re: new RegExp("^(?:" + p.pattern + ")$", "i"), result: p.result });
                } catch (e) {
                    console.warn(`[Translate] bad pattern in ${key}: ${p.pattern}`);
                }
            }
            if (arr.length > 0)
                out[key] = arr;
        }
        root._patterns = out;
    }

    function tryPatterns(text, source, target) {
        const clean = text.trim();
        const keys = source === "auto"
            ? Object.keys(root._patterns).filter(k => k.endsWith(`|${target}`))
            : [`${source}|${target}`];
        for (const key of keys) {
            const list = root._patterns[key];
            if (!list)
                continue;
            const map = root._wordmaps[key] ?? {};
            for (const p of list) {
                const m = p.re.exec(clean);
                if (!m)
                    continue;
                const out = p.result.split("$$").join("\0").replace(/\$(\d+)/g, (s, n) => {
                    const g = m[parseInt(n, 10)] ?? "";
                    return root.applyWordMap(g, map).text;
                }).split("\0").join("$");
                const final = out.replace(/\s+/g, " ").trim();
                if (!final)
                    continue;
                return { text: final, source: key.split("|")[0] };
            }
        }
        return null;
    }

    // Dynamic fallback: compose a translation word-by-word. Returns null
    // unless at least one word translated (zero hits is a miss, never a
    // fake success). Grammar is NOT handled — this is mechanical aid only.
    function composeWords(text, source, target) {
        if (source === "auto") {
            let best = null;
            for (const key of Object.keys(root._wordmaps)) {
                if (!key.endsWith(`|${target}`))
                    continue;
                const map = root._wordmaps[key];
                const hits = root.countHits(text, map);
                if (hits > 0 && (!best || hits > best.hits))
                    best = { src: key.split("|")[0], map: map, hits: hits };
            }
            if (!best)
                return null;
            const r = root.applyWordMap(text, best.map);
            return { source: best.src, text: r.text, translated: r.translated, total: r.total };
        }
        const map = root._wordmaps[`${source}|${target}`];
        if (!map)
            return null;
        const r = root.applyWordMap(text, map);
        return { source: source, text: r.text, translated: r.translated, total: r.total };
    }

    FileView {
        id: phrasebookStorage

        printErrors: false
        path: `${Quickshell.shellDir}/modules/launcher/services/phrasebook.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data && typeof data === "object" && !Array.isArray(data)) {
                    root._phrasebook = data;
                    root.buildWordMaps();
                    root.buildPatterns();
                    console.info(`[Translate] phrasebook loaded: ${Object.keys(data).length} tables`);
                } else {
                    console.warn("[Translate] phrasebook.json is not an object; offline engine disabled");
                }
            } catch (e) {
                console.warn("[Translate] phrasebook.json invalid: " + e);
            }
        }
        onLoadFailed: err => {
            console.warn("[Translate] phrasebook.json not loaded: " + err);
        }
    }

    function translateLocal(text: string, source: string, target: string, generation: int, remoteError: string): void {
        if (generation !== undefined && generation !== root._generation) {
            console.info(`[Translate] Request #${generation} ignored: stale request`);
            return;
        }
        const table = _phrasebook[`${source}|${target}`];
        let hit = table ? table[text.toLowerCase()] : undefined;
        let hitSource = source;
        if (hit === undefined && source === "auto") {
            // Offline auto-detect: scan the phrasebooks for this target and
            // use the first exact match. Remote providers detect server-side;
            // offline has no detector, so a table scan is the deterministic
            // equivalent for this small built-in phrasebook.
            for (const key of Object.keys(_phrasebook)) {
                if (key.endsWith(`|${target}`)) {
                    const t2 = _phrasebook[key];
                    const h2 = t2 ? t2[text.toLowerCase()] : undefined;
                    if (h2 !== undefined) {
                        hit = h2;
                        hitSource = key.split("|")[0];
                        break;
                    }
                }
            }
        }
        if (hit === undefined) {
            const pat = root.tryPatterns(text, source, target);
            if (pat) {
                hit = pat.text;
                hitSource = pat.source;
            }
        }
        if (hit !== undefined) {
            root.result = hit;
            root.detectedSource = source === "auto" ? languageName(hitSource) : "";
            root.error = "";
            root.pushHistory(text, hit);
        } else {
            // Dynamic fallback: compose word-by-word from the word resources
            // (explicit "words" plus auto-derived single-word pairs).
            const composed = root.composeWords(text, source, target);
            if (composed && composed.translated > 0) {
                root.result = composed.text;
                root.detectedSource = source === "auto" ? languageName(composed.source) : "";
                root.error = "";
                root.pushHistory(text, composed.text);
            } else {
                root.result = "";
                // Name the limitation: the offline engine only covers common
                // greetings (see _phrasebook). Anything else needs a network
                // engine, so point there instead of a bare failure.
                root.error = remoteError || Tr.tr("Not in the offline phrasebook — switch to the MyMemory or Google engine");
            }
        }
        // Finish here: result/error are final, so completion can be announced.
        if (generation !== undefined)
            root.complete(generation);
    }

    function persistHistory(): void {
        historyStorage.setText(JSON.stringify(history));
    }

    FileView {
        id: historyStorage

        printErrors: false
        path: `${Paths.state}/translate-history.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (Array.isArray(data))
                    root.history = data.slice(0, root.maxHistory);
            } catch (e) {
                // Corrupt history is not fatal; start empty.
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText("[]"));
        }
    }

    onProviderIdChanged: providerStorage.setText(providerId)

    FileView {
        id: providerStorage

        printErrors: false
        path: `${Paths.state}/translate-provider.txt`
        onLoaded: {
            const saved = text().trim();
            if (root.providers.some(p => p.id === saved) && saved !== root.providerId)
                root.providerId = saved;
            else if (!root.providers.some(p => p.id === saved))
                setText(root.providerId);
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(root.providerId));
        }
    }
}
