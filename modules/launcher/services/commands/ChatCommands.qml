import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.modules.launcher.services
import qs.modules.nexus

// Ask-AI commands. `ask <question>` answers one-shot (toast + clipboard,
// launcher stays open); `chat [question]` opens Nexus AI Chat and sends
// the rest of the line as the first prompt.
// Both reuse ChatService (free Pollinations backend, no key); no second
// backend exists anywhere.
QtObject {
    id: root

    // One-shot: toast + full answer to clipboard, generation-matched so a
    // late older answer can never overwrite a newer one.
    property int _oneShotGen: -1
    property var _oneShotReport: null
    property string _oneShotInput: ""

    function parseAsk(raw) {
        const s = (raw ?? "").trim();
        if (!s)
            return { ok: false, error: Tr.tr("What should I ask?") };
        return { ok: true, value: { text: s } };
    }

    function parseChat(raw) {
        return { ok: true, value: { text: (raw ?? "").trim() } };
    }

    function startAsk(v, report) {
        root._oneShotReport = report;
        root._oneShotInput = v.text;
        // Expecting: adopt from finished if this completes synchronously;
        // otherwise adopt the current id right after.
        root._oneShotGen = -2;
        ChatService.ask(v.text);
        if (root._oneShotGen === -2)
            root._oneShotGen = ChatService.currentRequestId;
    }

    property Connections askConn: Connections {
        target: ChatService

        function onFinished(generation, response, error): void {
            root.handleAskFinished(generation, response, error);
        }
    }

    function handleAskFinished(generation, response, error) {
        if (root._oneShotGen === -2)
            root._oneShotGen = generation;
        if (!root._oneShotReport || generation !== root._oneShotGen) {
            console.info(`[Chat] one-shot ignored finished #${generation} (waiting for #${root._oneShotGen})`);
            return;
        }
        const report = root._oneShotReport;
        const input = root._oneShotInput;
        root._oneShotReport = null;
        root._oneShotGen = -1;
        root._oneShotInput = "";
        console.info(`[Chat] one-shot #${generation} notification shown`);

        if (error && !response) {
            report({ title: Tr.tr("Ask"), message: error, icon: "error", type: "error" });
            return;
        }
        const out = response ?? "";
        if (!out) {
            report({ title: Tr.tr("Ask"), message: Tr.tr("The service returned an empty answer."), icon: "error", type: "error" });
            return;
        }
        Quickshell.clipboardText = out;
        if (out.length <= 100) {
            report({ title: Tr.tr("Ask"), message: input + " => " + out, icon: "smart_toy", type: "success" });
        } else {
            report({ title: Tr.tr("Ask"), message: Tr.tr("answer too long, copied to clipboard"), icon: "smart_toy", type: "success" });
        }
    }

    readonly property var commands: [
        {
            name: "Ask",
            aliases: ["ai"],
            description: Tr.tr("Ask AI anything (free, no key)"),
            icon: "smart_toy",
            category: Tr.tr("AI"),
            keepOpen: true,
            args: {
                type: "custom",
                required: true,
                parse: root.parseAsk,
                hint: "question"
            },
            run: (v, report) => root.startAsk(v, report)
        },
        {
            name: "Chat",
            aliases: ["chatbot"],
            description: Tr.tr("Open AI chat in Nexus"),
            icon: "forum",
            category: Tr.tr("AI"),
            // Bare `chat` opens Nexus immediately instead of a fill stub.
            runBare: true,
            // The launcher is only the entry point; closing it hands the
            // conversation to the larger Nexus window.
            keepOpen: false,
            args: {
                type: "custom",
                required: false,
                parse: root.parseChat,
                hint: "optional question"
            },
            run: (v, report) => {
                WindowFactory.openChat(v?.text ?? "");
            }
        }
    ]
}
