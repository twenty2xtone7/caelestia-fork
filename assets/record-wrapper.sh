#!/usr/bin/env sh
# Launcher for `caelestia record` used by the shell's recorder service
# (see services/Recorder.qml). It runs the exact same command as pressing
# the record button / running `caelestia record` in a terminal.
#
# Why this exists: gpu-screen-recorder inherits our stdio. When the shell
# spawns this command, its stdout/stderr are pipes that close once this
# command exits, but the recorder keeps logging for the whole recording -
# its next log write then dies from SIGPIPE (exit code -13) a few seconds
# in. Redirecting to a log file (and stdin from DEVNULL, verified harmless)
# makes shell-started recordings survive exactly like terminal-started ones.
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/record"
mkdir -p "$LOG_DIR"
exec caelestia record "$@" </dev/null >>"$LOG_DIR/launcher.log" 2>&1
