pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property alias running: props.running
    readonly property alias paused: props.paused
    readonly property alias elapsed: props.elapsed
    property int refCount: 0
    property bool needsStart
    property list<string> startArgs
    property bool needsStop
    property bool needsPause

    // Wrapper that runs `caelestia record` with file-backed stdio, so the
    // recorder process can never SIGPIPE on inherited pipes that close once
    // the command exits (see assets/record-wrapper.sh). Same command the
    // record button / a terminal would run, just survivable stdio.
    readonly property string wrapper: `${Quickshell.shellDir}/assets/record-wrapper.sh`

    function start(extraArgs = []): void {
        needsStart = true;
        startArgs = extraArgs;
        checkProc.running = true;
    }

    function stop(): void {
        needsStop = true;
        checkProc.running = true;
    }

    function togglePause(): void {
        needsPause = true;
        checkProc.running = true;
    }

    PersistentProperties {
        id: props

        property bool running: false
        property bool paused: false
        property real elapsed: 0 // Might get too large for int

        reloadableId: "recorder"
    }

    Process {
        id: checkProc

        running: true
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => { // qmllint disable signal-handler-parameters
            const running = code === 0;

            if (running && root.needsStop) {
                commandProc.exec([root.wrapper]);
                props.running = false;
                props.paused = false;
            } else if (running && root.needsPause) {
                commandProc.exec([root.wrapper, "-p"]);
                props.paused = !props.paused;
            } else if (!running && root.needsStart) {
                commandProc.exec([root.wrapper, ...root.startArgs]);
                props.running = true;
                props.paused = false;
                props.elapsed = 0;
            } else if (running !== props.running && !commandProc.running) {
                // The recording was started/stopped outside the shell (e.g. via
                // keybind), or our command finished without reaching the optimistic state
                props.running = running;
                props.paused = false;
                props.elapsed = 0;
            }

            root.needsStart = false;
            root.needsStop = false;
            root.needsPause = false;
        }
    }

    Process {
        id: commandProc

        // The command owns the transition: `caelestia record` blocks on slurp for
        // region captures, and waits for the recorder to finalise the file when
        // stopping. Reconcile once it has actually finished.
        onExited: checkProc.running = true // qmllint disable signal-handler-parameters
    }

    // Poll while the drawer is open (to catch externally started/stopped
    // recordings, e.g. via keybind) and while a recording is supposedly
    // active. The latter is the self-heal: if gpu-screen-recorder dies or was
    // never really running (stale persisted state after a restart, external
    // kill, early encoder failure), the next check clears the stuck
    // "Running..." UI instead of showing it forever with a ticking timer.
    // In-flight operations are safe: the reconcile branch below refuses to
    // clear state while commandProc is still running (e.g. region selection
    // blocking on slurp), and the CLI itself waits ~1s for the recorder
    // process to appear before reporting success.
    Timer {
        interval: 1000
        running: root.refCount > 0 || props.running
        repeat: true
        triggeredOnStart: true

        onTriggered: checkProc.running = true
    }

    Connections {
        function onSecondsChanged(): void {
            props.elapsed++;
        }

        enabled: props.running && !props.paused
        target: Time // qmllint disable incompatible-type
    }
}
