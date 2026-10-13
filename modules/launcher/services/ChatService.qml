pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.I18n
import qs.utils

// Free AI backend for launcher ask + Nexus AI Chat.
//
// Sessions are the conversation. Each one keeps its own messages, and the
// active session is restored when Nexus AI Chat opens. The request itself
// lives here, not in the window, so closing Nexus does not cancel a reply.
//
// Streaming tokens stay in `response` until the reply is finished. The
// sessions list is not rewritten on every chunk — that froze the shell.
Singleton {
    id: root

    readonly property string endpoint: "https://text.pollinations.ai/"
    readonly property string streamEndpoint: "https://text.pollinations.ai/openai"

    property string status: ""
    readonly property string backendLabel: Tr.tr("Free · about one message every 15 seconds")

    property string input: ""
    property string response: ""
    property bool asking: false
    property string error: ""

    // { id, title, updated, messages: [{role, content}] }
    property list<var> sessions: []
    property string activeSessionId: ""
    readonly property int maxSessions: 30
    readonly property int maxMessages: 80

    property list<var> history: []
    readonly property int maxHistory: 20

    property int _generation: 0
    readonly property int currentRequestId: _generation
    property string _streamQuestion: ""
    property string _streamSessionId: ""
    readonly property bool streamingHere: asking && _streamSessionId === activeSessionId
    property string _rawAcc: ""
    property string _pendingDelta: ""
    property bool _ignoreNextExit: false
    property bool _suppressStream: false
    property bool _loaded: false
    property int _providerIndex: 0
    property var _providerPlan: []
    property real _lastPollinations: 0

    signal finished(int generation, string response, string error)

    readonly property var activeSession: sessions.find(s => s.id === activeSessionId) ?? null
    readonly property var messages: activeSession?.messages ?? []

    function newId(): string {
        return `${Date.now().toString(36)}${Math.floor(Math.random() * 1e6).toString(36)}`;
    }

    function titleFrom(text: string): string {
        const s = (text ?? "").replace(/\s+/g, " ").trim();
        if (!s)
            return Tr.tr("New chat");
        return s.length > 42 ? s.slice(0, 41) + "…" : s;
    }

    function ensureSession(): string {
        if (activeSession)
            return activeSessionId;
        return createSession(true);
    }

    function createSession(activate: bool): string {
        const session = {
            id: newId(),
            title: Tr.tr("New chat"),
            updated: Date.now(),
            messages: []
        };
        sessions = [session, ...sessions].slice(0, maxSessions);
        if (activate !== false)
            activeSessionId = session.id;
        scheduleSave();
        return session.id;
    }

    function switchSession(id: string): void {
        if (!sessions.some(s => s.id === id))
            return;
        activeSessionId = id;
        const session = sessions.find(s => s.id === id);
        const last = (session?.messages ?? []).slice().reverse().find(m => m.role === "assistant" && m.content);
        response = last ? String(last.content) : "";
        error = "";
        scheduleSave();
    }

    function deleteSession(id: string): void {
        const next = sessions.filter(s => s.id !== id);
        sessions = next;
        if (activeSessionId === id)
            activeSessionId = next[0]?.id ?? "";
        if (!activeSessionId)
            createSession(true);
        scheduleSave();
    }

    function replaceActive(mutator): void {
        const id = ensureSession();
        const next = sessions.map(s => {
            if (s.id !== id)
                return s;
            const copy = {
                id: s.id,
                title: s.title,
                updated: Date.now(),
                messages: (s.messages ?? []).slice()
            };
            mutator(copy);
            if (copy.messages.length > root.maxMessages)
                copy.messages = copy.messages.slice(-root.maxMessages);
            return copy;
        });
        sessions = next;
        scheduleSave();
    }

    function restoreMessages(): void {
        if (_loaded) {
            if (!activeSession)
                createSession(true);
            return;
        }
        const raw = sessionStorage.text().trim();
        if (raw)
            applyStored(raw);
    }

    function apiMessages(): var {
        const out = [{
                role: "system",
                content: "You are a helpful assistant in the Caelestia desktop shell."
            }];
        const src = messages.filter(m => (m.role === "user" || m.role === "assistant") && String(m.content ?? "").length > 0);
        const trimmed = src.slice(-12);
        for (const m of trimmed) {
            out.push({
                role: m.role,
                content: String(m.content ?? "")
            });
        }
        return out;
    }

    function buildPrompt(q: string): string {
        const turns = messages.filter(m => (m.role === "user" || m.role === "assistant") && String(m.content ?? "").length > 0);
        const prior = turns.slice(-6);
        if (prior.length === 0)
            return q;
        const lines = [];
        let budget = 3000;
        for (let i = 0; i < prior.length; i += 2) {
            const hq = prior[i]?.role === "user" ? String(prior[i].content).slice(0, 300) : "";
            const ha = prior[i + 1]?.role === "assistant" ? String(prior[i + 1].content).slice(0, 500) : "";
            if (!hq)
                continue;
            const block = `User: ${hq}\nAssistant: ${ha}`;
            if (block.length + 1 > budget)
                continue;
            budget -= block.length + 1;
            lines.push(block);
        }
        if (lines.length === 0)
            return q;
        return lines.join("\n") + `\nUser: ${q}\nAssistant:`;
    }

    function appendUser(q: string): void {
        replaceActive(session => {
            if (session.title === Tr.tr("New chat") || !session.title)
                session.title = root.titleFrom(q);
            session.messages.push({
                role: "user",
                content: q
            });
        });
    }

    function commitAssistant(text: string): void {
        const out = (text ?? "").trim();
        if (!out)
            return;
        replaceActive(session => {
            session.messages.push({
                role: "assistant",
                content: out
            });
        });
    }

    function flushStream(): void {
        if (!_pendingDelta)
            return;
        response += _pendingDelta;
        _pendingDelta = "";
    }

    function appendDelta(delta: string): void {
        if (!delta)
            return;
        _pendingDelta += delta;
        if (!flushTimer.running)
            flushTimer.start();
    }

    function markError(message: string): void {
        root.error = message;
        replaceActive(session => {
            session.messages.push({
                role: "error",
                content: message
            });
        });
    }

    function looksLimited(text: string): bool {
        const s = (text ?? "").toLowerCase();
        return s.includes("rate limit") || s.includes("too many") || s.includes("429") || s.includes("quota");
    }

    function startProviders(generation: int): void {
        const plan = ["pollinations"];
        _providerPlan = plan;
        _providerIndex = 0;
        runProvider(generation);
    }

    function runProvider(generation: int): void {
        if (generation !== _generation)
            return;
        const kind = _providerPlan[_providerIndex] ?? "";
        if (!kind) {
            markError(Tr.tr("No AI backend available"));
            complete(generation);
            return;
        }

        if (kind === "pollinations") {
            const wait = 16000 - (Date.now() - _lastPollinations);
            if (_lastPollinations > 0 && wait > 250) {
                status = Tr.tr("Free service is cooling down…");
                cooldown.interval = Math.min(wait, 16000);
                cooldown.restart();
                return;
            }
            _lastPollinations = Date.now();
        }

        status = Tr.tr("Asking free service…");
        response = "";
        _pendingDelta = "";
        _rawAcc = "";

        const payload = JSON.stringify({
            model: "openai-fast",
            stream: true,
            messages: root.apiMessages()
        });

        streamProc.command = ["curl", "-N", "-sS", "--max-time", "90", "-H", "Content-Type: application/json", "-H", "Accept: text/event-stream", "-d", payload, streamEndpoint];
        _suppressStream = false;
        streamProc.running = true;
        watchdog.restart();
    }

    function nextProvider(generation: int): void {
        if (generation !== _generation)
            return;
        _providerIndex += 1;
        if (_providerIndex >= _providerPlan.length) {
            markError(Tr.tr("The AI service is rate-limited — wait a few seconds and try again"));
            complete(generation);
            return;
        }
        console.info(`[Chat] Request #${generation} switching provider to ${_providerPlan[_providerIndex]}`);
        runProvider(generation);
    }

    function ask(text: string): int {
        const q = (text ?? root.input).trim();
        if (!q) {
            error = Tr.tr("Type a question first");
            return _generation;
        }

        ensureSession();

        if (streamProc.running) {
            _suppressStream = true;
            _ignoreNextExit = true;
            streamProc.running = false;
        }

        flushTimer.stop();
        _pendingDelta = "";

        const generation = ++_generation;
        console.info(`[Chat] Request #${generation} started q="${q.slice(0, 80)}" session=${activeSessionId}`);
        asking = true;
        error = "";
        response = "";
        input = q;
        _streamQuestion = q;
        _streamSessionId = activeSessionId;
        _rawAcc = "";

        appendUser(q);
        startProviders(generation);
        return generation;
    }

    function handleStreamLine(line: string): void {
        if (root._suppressStream)
            return;
        const s = (line ?? "").trim();
        if (!s)
            return;

        if (s.startsWith("data:")) {
            const data = s.slice(5).trim();
            if (!data || data === "[DONE]")
                return;
            try {
                const json = JSON.parse(data);
                const delta = json?.choices?.[0]?.delta?.content ?? json?.choices?.[0]?.message?.content ?? "";
                if (delta)
                    root.appendDelta(String(delta));
            } catch (e) {
            }
            return;
        }

        if (s.startsWith(":"))
            return;

        if (root._rawAcc.length < 20000)
            root._rawAcc += s;
        try {
            const json = JSON.parse(s);
            const delta = json?.choices?.[0]?.delta?.content ?? json?.choices?.[0]?.message?.content ?? "";
            if (delta)
                root.appendDelta(String(delta));
        } catch (e) {
        }
    }

    function finishSuccess(generation: int, text: string): void {
        if (generation !== root._generation)
            return;
        const out = (text ?? "").trim();
        root.response = out;
        root.error = "";
        root.commitAssistant(out);
        root.pushHistory(root._streamQuestion, out);
        root.complete(generation);
    }

    function handleStreamExit(code: int): void {
        root.flushStream();
        const generation = root._generation;
        if (root.response.trim() && !root.looksLimited(root.response)) {
            root.finishSuccess(generation, root.response);
            return;
        }

        let parsed = "";
        let failed = false;
        if (root._rawAcc) {
            try {
                const json = JSON.parse(root._rawAcc);
                if (json?.error) {
                    failed = true;
                    parsed = String(json.error.message ?? "");
                } else {
                    parsed = String(json?.choices?.[0]?.message?.content ?? json?.response ?? "");
                }
            } catch (e) {
                if (root._rawAcc.trim() && !root._rawAcc.trim().startsWith("{") && !root._rawAcc.trim().startsWith("<"))
                    parsed = root._rawAcc;
            }
        }

        if (failed || root.looksLimited(parsed)) {
            console.info(`[Chat] Request #${generation} provider failed (code=${code})`);
            root.nextProvider(generation);
            return;
        }

        if (parsed.trim() && !root.looksLimited(parsed)) {
            root.finishSuccess(generation, parsed);
            return;
        }

        console.info(`[Chat] Request #${generation} provider failed (code=${code})`);
        root.nextProvider(generation);
    }

    function complete(generation: int): void {
        if (generation !== root._generation) {
            console.info(`[Chat] Request #${generation} ignored: stale request`);
            return;
        }
        watchdog.stop();
        flushTimer.stop();
        cooldown.stop();
        _pendingDelta = "";
        _streamSessionId = "";
        status = "";
        root.asking = false;
        console.info(`[Chat] Request #${generation} accepted len=${root.response.length} error="${root.error}"`);
        finished(generation, root.response, root.error);
    }

    function pushHistory(question: string, answer: string): void {
        const entry = {
            q: question,
            a: answer,
            time: Date.now()
        };
        const next = [entry, ...history.filter(h => !(h.q === question && h.a === answer))];
        history = next.slice(0, maxHistory);
    }

    function clear(): void {
        input = "";
        response = "";
        error = "";
    }

    function clearHistory(): void {
        history = [];
    }

    function clearMessages(): void {
        if (streamProc.running) {
            _suppressStream = true;
            _ignoreNextExit = true;
            streamProc.running = false;
        }
        watchdog.stop();
        flushTimer.stop();
        cooldown.stop();
        _pendingDelta = "";
        status = "";
        asking = false;
        response = "";
        error = "";
        input = "";
        replaceActive(session => {
            session.messages = [];
            session.title = Tr.tr("New chat");
        });
    }

    function applyStored(raw: string): void {
        try {
            const data = JSON.parse(raw);
            const list = Array.isArray(data?.sessions) ? data.sessions : [];
            sessions = list.filter(s => s && s.id).slice(0, maxSessions).map(s => ({
                        id: String(s.id),
                        title: String(s.title || Tr.tr("New chat")),
                        updated: Number(s.updated) || 0,
                        messages: Array.isArray(s.messages) ? s.messages.slice(-root.maxMessages) : []
                    }));
            activeSessionId = sessions.some(s => s.id === data.activeSessionId) ? data.activeSessionId : (sessions[0]?.id ?? "");
            if (!activeSessionId)
                createSession(true);
            _loaded = true;
        } catch (e) {
            if (!sessions.length)
                createSession(true);
            _loaded = true;
        }
    }

    function scheduleSave(): void {
        if (!_loaded)
            return;
        saveTimer.restart();
    }

    function persist(): void {
        if (!_loaded)
            return;
        const payload = JSON.stringify({
            activeSessionId,
            sessions: sessions.map(s => ({
                    id: s.id,
                    title: s.title,
                    updated: s.updated,
                    messages: (s.messages ?? []).slice(-maxMessages)
                }))
        });
        sessionStorage.setText(payload);
    }

    Timer {
        id: flushTimer

        interval: 50
        repeat: false
        onTriggered: root.flushStream()
    }

    Timer {
        id: saveTimer

        interval: 400
        repeat: false
        onTriggered: root.persist()
    }

    Timer {
        id: cooldown

        interval: 16000
        repeat: false
        onTriggered: root.runProvider(root._generation)
    }

    Timer {
        id: watchdog

        interval: 130000
        repeat: false
        onTriggered: {
            if (!root.asking)
                return;
            if (streamProc.running) {
                root._suppressStream = true;
                root._ignoreNextExit = true;
                streamProc.running = false;
            }
            root.flushStream();
            if (root.response.trim())
                root.finishSuccess(root._generation, root.response);
            else
                root.nextProvider(root._generation);
        }
    }

    FileView {
        id: sessionStorage

        printErrors: false
        path: `${Paths.state}/chat-sessions.json`
        onLoaded: root.applyStored(text())
        onLoadFailed: err => {
            if (!root._loaded)
                root.createSession(true);
            root._loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => root.persist());
        }
    }

    Process {
        id: streamProc

        stdinEnabled: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handleStreamLine(data)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("[Chat] stream stderr:", text.trim().slice(0, 300));
            }
        }
        onExited: code => {
            if (root._ignoreNextExit) {
                root._ignoreNextExit = false;
                return;
            }
            if (root._generation <= 0)
                return;
            root.handleStreamExit(code);
        }
    }
}
