import QtQuick
import Quickshell
import Caelestia.Services
import Caelestia.I18n

// System power/session commands. Execution goes through the same
// Caelestia.Services.SessionManager the session menu and radial menu use,
// so there is no duplicate backend and logind/polkit handling is identical.
QtObject {
    readonly property var commands: [
        {
            name: "Reboot",
            aliases: ["restart"],
            description: Tr.tr("Restart the computer"),
            icon: "restart_alt",
            category: Tr.tr("System"),
            confirm: {
                title: Tr.tr("Restart computer?"),
                accept: Tr.tr("Restart")
            },
            run: (v, report) => {
                SessionManager.reboot();
                report({ title: Tr.tr("Rebooting"), message: "", icon: "restart_alt", type: "success" });
            }
        },
        {
            name: "Shutdown",
            aliases: ["poweroff", "power"],
            description: Tr.tr("Power off the computer"),
            icon: "power_settings_new",
            category: Tr.tr("System"),
            confirm: {
                title: Tr.tr("Shut down?"),
                accept: Tr.tr("Shut down")
            },
            run: (v, report) => {
                SessionManager.poweroff();
                report({ title: Tr.tr("Shutting down"), message: "", icon: "power_settings_new", type: "success" });
            }
        },
        {
            name: "Lock",
            aliases: [],
            description: Tr.tr("Lock the screen"),
            icon: "lock",
            category: Tr.tr("System"),
            run: (v, report) => {
                SessionManager.lockRequested();
                report({ title: Tr.tr("Screen locked"), message: "", icon: "lock", type: "success" });
            }
        },
        {
            name: "Logout",
            aliases: ["signout"],
            description: Tr.tr("Log out of the session"),
            icon: "logout",
            category: Tr.tr("System"),
            confirm: {
                title: Tr.tr("Log out?"),
                accept: Tr.tr("Log out")
            },
            run: (v, report) => {
                SessionManager.logout();
                report({ title: Tr.tr("Logging out"), message: "", icon: "logout", type: "success" });
            }
        },
        {
            name: "Suspend",
            aliases: ["sleep"],
            description: Tr.tr("Suspend the computer"),
            icon: "bedtime",
            category: Tr.tr("System"),
            confirm: {
                title: Tr.tr("Suspend?"),
                accept: Tr.tr("Suspend")
            },
            run: (v, report) => {
                SessionManager.suspend();
                report({ title: Tr.tr("Suspending"), message: "", icon: "bedtime", type: "success" });
            }
        }
    ]
}
