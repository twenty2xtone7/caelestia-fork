pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

Singleton {
    id: root

    // Reactive properties for system data
    property real cpuPercentage: 0.0
    property string cpuName: ""
    property real memoryUsed: 0.0
    property real memoryTotal: 0.0
    property real memoryPercentage: 0.0
    property real downloadSpeed: 0.0
    property real uploadSpeed: 0.0
    property var temperatures: ({})
    property var fanRpms: ({})
    property bool hasCpuConsumers: false
    property bool hasMemoryConsumers: false
    property bool hasNetworkConsumers: false
    property bool hasTemperatureConsumers: false
    property bool hasFanConsumers: false

    // Internal state
    property var _prevCpuStat: ({})
    property int _prevNetworkRxBytes: 0
    property int _prevNetworkTxBytes: 0

    // --- CPU Monitoring ---
    property int _cpuConsumerCount: 0
    function registerCpuConsumer(): void {
        _cpuConsumerCount++;
        hasCpuConsumers = _cpuConsumerCount > 0;
    }
    function unregisterCpuConsumer(): void {
        _cpuConsumerCount = Math.max(0, _cpuConsumerCount - 1);
        hasCpuConsumers = _cpuConsumerCount > 0;
    }

    Timer {
        id: cpuMonitorTimer
        running: root.hasCpuConsumers
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        repeat: true
        onTriggered: {
            JobQueue.submitJob(
                "cpu-stats",
                ["cat", "/proc/stat"],
                { cacheKey: "cpu-stats", timeoutMs: 2000, priority: 2 }
            ).then(output => _parseCpuStats(output)).catch(err => {
                console.warn("[SystemMonitor] CPU stats failed:", err);
            });
        }
    }

    function _parseCpuStats(text: string): void {
        const lines = text.split('\n');
        const cpuLine = lines.find(line => line.startsWith('cpu '));
        if (!cpuLine) return;

        const parts = cpuLine.split(/\s+/).filter(Boolean);
        if (parts.length < 9) return;

        const user = parseInt(parts[1]);
        const nice = parseInt(parts[2]);
        const system = parseInt(parts[3]);
        const idle = parseInt(parts[4]);
        const iowait = parseInt(parts[5]);
        const irq = parseInt(parts[6]);
        const softirq = parseInt(parts[7]);
        const steal = parseInt(parts[8]);

        const currentTotal = user + nice + system + idle + iowait + irq + softirq + steal;
        const currentIdle = idle + iowait;

        if (root._prevCpuStat.total !== undefined) {
            const totalDiff = currentTotal - root._prevCpuStat.total;
            const idleDiff = currentIdle - root._prevCpuStat.idle;
            if (totalDiff > 0) {
                root.cpuPercentage = 100 * (totalDiff - idleDiff) / totalDiff;
            }
        }

        root._prevCpuStat = { total: currentTotal, idle: currentIdle };
    }

    Component.onCompleted: {
        JobQueue.submitJob(
            "cpu-name",
            ["sh", "-c", "grep 'model name' /proc/cpuinfo | head -n 1 | cut -d: -f2 | sed 's/^ *//'"],
            { cacheKey: "cpu-name", timeoutMs: 3000 }
        ).then(output => {
            root.cpuName = output.trim();
        }).catch(() => {});
    }

    // --- Memory Monitoring ---
    property int _memoryConsumerCount: 0
    function registerMemoryConsumer(): void {
        _memoryConsumerCount++;
        hasMemoryConsumers = _memoryConsumerCount > 0;
    }
    function unregisterMemoryConsumer(): void {
        _memoryConsumerCount = Math.max(0, _memoryConsumerCount - 1);
        hasMemoryConsumers = _memoryConsumerCount > 0;
    }

    Timer {
        id: memoryMonitorTimer
        running: root.hasMemoryConsumers
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        repeat: true
        onTriggered: {
            JobQueue.submitJob(
                "memory-stats",
                ["cat", "/proc/meminfo"],
                { cacheKey: "memory-stats", timeoutMs: 2000, priority: 2 }
            ).then(output => _parseMemoryStats(output)).catch(err => {
                console.warn("[SystemMonitor] Memory stats failed:", err);
            });
        }
    }

    function _parseMemoryStats(text: string): void {
        const memTotalLine = text.split('\n').find(line => line.startsWith('MemTotal:'));
        const memAvailableLine = text.split('\n').find(line => line.startsWith('MemAvailable:'));

        if (memTotalLine && memAvailableLine) {
            const totalKb = parseInt(memTotalLine.split(/\s+/)[1]);
            const availableKb = parseInt(memAvailableLine.split(/\s+/)[1]);

            root.memoryTotal = totalKb / (1024 * 1024);
            root.memoryUsed = (totalKb - availableKb) / (1024 * 1024);
            root.memoryPercentage = 100 * (totalKb - availableKb) / totalKb;
        }
    }

    // --- Network Throughput Monitoring ---
    property int _networkConsumerCount: 0
    function registerNetworkConsumer(): void {
        _networkConsumerCount++;
        hasNetworkConsumers = _networkConsumerCount > 0;
    }
    function unregisterNetworkConsumer(): void {
        _networkConsumerCount = Math.max(0, _networkConsumerCount - 1);
        hasNetworkConsumers = _networkConsumerCount > 0;
    }

    Timer {
        id: networkMonitorTimer
        running: root.hasNetworkConsumers
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        repeat: true
        onTriggered: {
            JobQueue.submitJob(
                "network-stats",
                ["sh", "-c", "cat /sys/class/net/*/statistics/rx_bytes 2>/dev/null; echo ---; cat /sys/class/net/*/statistics/tx_bytes 2>/dev/null"],
                { cacheKey: "network-stats", timeoutMs: 2000, priority: 2 }
            ).then(output => _parseNetworkStats(output)).catch(err => {
                console.warn("[SystemMonitor] Network stats failed:", err);
            });
        }
    }

    function _parseNetworkStats(text: string): void {
        const sections = text.trim().split("---");
        if (sections.length < 2) return;

        const currentRx = [];
        const currentTx = [];
        sections[0].split("\n").filter(l => l.trim()).forEach(l => {
            const v = parseInt(l);
            if (!isNaN(v)) currentRx.push(v);
        });
        sections[1].split("\n").filter(l => l.trim()).forEach(l => {
            const v = parseInt(l);
            if (!isNaN(v)) currentTx.push(v);
        });

        const sum = arr => arr.reduce((a, b) => a + b, 0);
        const curRxTotal = sum(currentRx);
        const curTxTotal = sum(currentTx);

        if (root._prevNetworkRxBytes !== undefined) {
            const intervalSeconds = networkMonitorTimer.interval / 1000;
            const diffRx = curRxTotal - root._prevNetworkRxBytes;
            const diffTx = curTxTotal - root._prevNetworkTxBytes;
            root.downloadSpeed = diffRx / intervalSeconds;
            root.uploadSpeed = diffTx / intervalSeconds;
        }

        root._prevNetworkRxBytes = curRxTotal;
        root._prevNetworkTxBytes = curTxTotal;
    }

    // --- Temperature Monitoring ---
    property int _temperatureConsumerCount: 0
    function registerTemperatureConsumer(): void {
        _temperatureConsumerCount++;
        hasTemperatureConsumers = _temperatureConsumerCount > 0;
    }
    function unregisterTemperatureConsumer(): void {
        _temperatureConsumerCount = Math.max(0, _temperatureConsumerCount - 1);
        hasTemperatureConsumers = _temperatureConsumerCount > 0;
    }

    Timer {
        id: temperatureMonitorTimer
        running: root.hasTemperatureConsumers
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        repeat: true
        onTriggered: {
            JobQueue.submitJob(
                "temperature-stats",
                ["sh", "-c", "sensors -j 2>/dev/null || echo '{}'"],
                { cacheKey: "temperature-stats", timeoutMs: 3000, priority: 1 }
            ).then(output => _parseTemperatureStats(output)).catch(err => {
                console.warn("[SystemMonitor] Temperature stats failed:", err);
            });
        }
    }

    function _parseTemperatureStats(text: string): void {
        try {
            const json = JSON.parse(text);
            const newTemps = {};
            for (const chipName in json) {
                for (const featureName in json[chipName]) {
                    if (featureName.startsWith('temp')) {
                        const tempObj = json[chipName][featureName];
                        const current = tempObj['temp1_input'] ?? tempObj['temp_input'];
                        const high = tempObj['temp1_crit'] ?? tempObj['temp_crit'];
                        const crit = tempObj['temp1_max'] ?? tempObj['temp_max'];

                        if (current !== undefined) {
                            newTemps[`${chipName}-${featureName}`] = {
                                current: current,
                                high: high,
                                crit: crit
                            };
                        }
                    }
                }
            }
            root.temperatures = newTemps;
        } catch (e) {
            console.warn("[SystemMonitor] Failed to parse sensors:", e.message);
            root.temperatures = {};
        }
    }

    // --- Fan RPM Monitoring ---
    property int _fanConsumerCount: 0
    function registerFanConsumer(): void {
        _fanConsumerCount++;
        hasFanConsumers = _fanConsumerCount > 0;
    }
    function unregisterFanConsumer(): void {
        _fanConsumerCount = Math.max(0, _fanConsumerCount - 1);
        hasFanConsumers = _fanConsumerCount > 0;
    }

    Timer {
        id: fanMonitorTimer
        running: root.hasFanConsumers
        interval: GlobalConfig.dashboard.resourceUpdateInterval
        repeat: true
        onTriggered: {
            JobQueue.submitJob(
                "fan-stats",
                ["sh", "-c", "sensors -j 2>/dev/null || echo '{}'"],
                { cacheKey: "fan-stats", timeoutMs: 3000, priority: 1 }
            ).then(output => _parseFanStats(output)).catch(err => {
                console.warn("[SystemMonitor] Fan stats failed:", err);
            });
        }
    }

    function _parseFanStats(text: string): void {
        try {
            const json = JSON.parse(text);
            const newFans = {};
            for (const chipName in json) {
                for (const featureName in json[chipName]) {
                    if (featureName.startsWith('fan')) {
                        const fanRpm = json[chipName][featureName]['fan1_input'] ?? json[chipName][featureName]['fan_input'];
                        if (fanRpm !== undefined) {
                            newFans[`${chipName}-${featureName}`] = fanRpm;
                        }
                    }
                }
            }
            root.fanRpms = newFans;
        } catch (e) {
            console.warn("[SystemMonitor] Failed to parse fan data:", e.message);
            root.fanRpms = {};
        }
    }

    // React to interval changes
    Connections {
        target: GlobalConfig.dashboard
        function onResourceUpdateIntervalChanged(): void {
            cpuMonitorTimer.interval = GlobalConfig.dashboard.resourceUpdateInterval;
            memoryMonitorTimer.interval = GlobalConfig.dashboard.resourceUpdateInterval;
            networkMonitorTimer.interval = GlobalConfig.dashboard.resourceUpdateInterval;
            temperatureMonitorTimer.interval = GlobalConfig.dashboard.resourceUpdateInterval;
            fanMonitorTimer.interval = GlobalConfig.dashboard.resourceUpdateInterval;
        }
    }
}
