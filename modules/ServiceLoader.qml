import QtQuick
import Quickshell
import Caelestia.Config
import qs.services
import qs.modules.launcher.services
import qs.utils

Scope {
    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        IdleInhibitor;
        GameMode;
        Night;
        Radial;
        Notifs;
        Players;
        Brightness;
        LiquidGlass;
        Weather.reload();

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;

        ClipboardService;
        CommandRegistry;
        FanCtl;
        SystemMonitor;
        WorkerSupervisor;
        JobQueue;
        RainbowAnimator;
        
        // JobQueue tests disabled in production to avoid startup object churn.
    }
}
