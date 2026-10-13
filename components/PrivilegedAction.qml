pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

/**
 * PrivilegedAction: Execute privileged actions via sudo with PAM auth.
 * Shows built-in password/fingerprint prompt instead of external Polkit popup.
 * 
 * Usage:
 *   PrivilegedAction {
 *       id: rebootWindows
 *       command: ["/home/twenty2xtone/.local/bin/caelestia-reboot-windows"]
 *       onSuccess: console.log("Success")
 *       onError: (msg) => console.log("Error:", msg)
 *       onAuthRequired: { ... show dialog ... }
 *   }
 *   rebootWindows.execute()
 */

Scope {
    id: root

    required property list<string> command

    signal success()
    signal error(string message)
    signal authRequired()
    signal authCancelled()

    property bool executing: false
    property string lastPassword: ""

    function execute(): void {
        if (executing) return;
        executing = true;
        root.authRequired();
        pam.start();
    }

    function submitPassword(pwd: string): void {
        if (!executing) {
            executing = true;
            root.authRequired();
        }
        lastPassword = pwd;
        if (!pam.active)
            pam.start();
        else
            pam.respond(pwd);
    }

    function abort(): void {
        pam.abort();
        executing = false;
        root.authCancelled();
    }

    PamContext {
        id: pam
        config: "sudo"
        configDirectory: Quickshell.shellPath("assets/pam.d")

        onResponseRequiredChanged: {
            if (responseRequired && lastPassword) {
                respond(lastPassword);
                lastPassword = ""; // Clear immediately
            }
        }

        onCompleted: res => {
            root.executing = false;
            lastPassword = ""; // Clear on completion

            if (res === PamResult.Success) {
                proc.running = true;
            } else if (res === PamResult.Failed) {
                root.error("Authentication failed");
            } else if (res === PamResult.MaxTries) {
                root.error("Maximum authentication attempts reached");
            } else {
                root.error(`Authentication error: ${res}`);
            }
        }
    }

    Process {
        id: proc

        command: ["sudo", "-u", "root"] + root.command

        onExited: exitCode => {
            if (exitCode === 0) {
                root.success();
            } else {
                root.error(`Command failed with exit code ${exitCode}`);
            }
        }
    }
}
