pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Scope {
    id: root

    enum AuthState { Idle, Loading, Error, Success, Fingerprint }

    readonly property bool available: fprint.available || howdy.available

    readonly property int state: pam.state === Pam.MaxTries ? AuthState.Error :
                                 pam.active ? AuthState.Loading :
                                 fprint.active || howdy.active ? AuthState.Fingerprint : AuthState.Idle

    function startAuth(): void {
        if (fprint.canAttempt) {
            fprint.start();
        } else if (howdy.canAttempt) {
            howdy.start();
        } else {
            pam.start();
        }
    }

    function abortAuth(): void {
        pam.abort();
        fprint.abort();
        howdy.abort();
    }

    // Native PAM contexts
    PamContext {
        id: pam
        config: "passwd"
        configDirectory: Quickshell.shellPath("assets/pam.d")
    }

    ManualPamContext {
        id: fprint
        config: "fprint"
        availCommand: ["sh", "-c", "fprintd-list $USER"]
        retryOnFail: true
        enabled: true
        maxTries: 3
    }

    ManualPamContext {
        id: howdy
        config: "howdy"
        availCommand: ["sh", "-c", "command -v howdy"]
        enabled: false
        maxTries: 3
    }

    // Signal emitted when native PAM authenticates (password or biometric)
    signal authenticated(string response)

    // Override onCompleted to emit our custom signal so callers can proceed
    PamContext.onCompleted: res => {
        if (res === PamResult.Success) {
            root.authenticated(root.pam.message);
        }
    }
}

component ManualPamContext: Scope {
    id: ctx
    required property bool enabled
    required property int maxTries
    property alias config: pam.config
    property alias availCommand: availProc.command
    property bool retryOnFail

    property bool available
    property int tries
    property int errorTries
    property int state
    readonly property bool canAttempt: available && enabled && tries < maxTries

    readonly property alias active: pam.active
    readonly property alias message: pam.message

    signal availProcExited(code: int)

    function checkAvailable(): void {
        availProc.running = true;
    }

    function start(): void {
        pam.start();
    }

    function abort(): void {
        pam.abort();
    }

    function reset(): void {
        tries = 0;
        errorTries = 0;
        state = 0;
    }

    Component.onCompleted: {
        checkAvailable();
    }

    Connections {
        function onAvailProcFinished(): void {
            available = availProc.exitCode === 0;
            availProcExited(availProc.exitCode);
        }
        target: availProc
    }

    PamContext {
        id: pam
        config: ctx.config
        configDirectory: Quickshell.shellPath("assets/pam.d")

        onResponseRequiredChanged: {
            if (responseRequired) {
                respond(ctx.lastInput);
                ctx.lastInput = "";
            }
        }

        onCompleted: res => {
            if (res === PamResult.Success) {
                ctx.state = 0;
            } else if (res === PamResult.Error) {
                ctx.state = 2;
                if (ctx.errorTries < ctx.maxTries) {
                    ctx.errorTries++;
                    // Allow retry if error was transient
                }
            } else if (res === PamResult.Failed || res === PamResult.MaxTries) {
                ctx.state = 1; // Failed
                if (ctx.retryOnFail && ctx.tries < ctx.maxTries) {
                    ctx.tries++;
                    ctx.state = 0; // Reset for retry
                }
            }
        }
    }

    Process {
        id: availProc
        command: ctx.availCommand
        onFinished: {
            ctx.checkAvailable();
        }
    }
}
