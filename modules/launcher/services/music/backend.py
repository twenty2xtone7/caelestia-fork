#!/usr/bin/env python3
"""
Caelestia Music Backend — persistent JSON-Lines server.

Reads newline-delimited JSON commands from stdin, writes
newline-delimited JSON responses to stdout.

Commands:
  {"action":"search","query":"..."}          → search results via yt-dlp
  {"action":"resolve","url":"..."}            → resolve a playable audio URL
  {"action":"download","url":"...","title":"...","artist":"..."}
                                                → download to ~/Music/Caelestia/
  {"action":"library"}                         → list downloaded tracks
  {"action":"check_deps"}                      → check python3/yt-dlp/ffmpeg
  {"action":"mpris_state", ...}                → publish playback state on MPRIS

Process lifecycle:
  - Runs until stdin is closed (EOF) or SIGTERM/SIGINT.
  - One download at a time; searches are cancelled when a new one arrives.
  - A GLib thread serves org.mpris.MediaPlayer2.caelestia when
    dbus-python + PyGObject are available, so the MPRIS-driven
    dashboard media card, lyrics and media keys see launcher playback.
    Incoming transport calls are forwarded to QML as
    {"type":"mpris_command",...} lines.
"""

from __future__ import annotations

import json
import os
import queue as _queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

# ── Constants ────────────────────────────────────────────────────────
MUSIC_DIR = Path.home() / "Music" / "Caelestia"
DEBOUNCE_SECONDS = 0.4
MAX_RESULTS = 12


def log(msg: str) -> None:
    """Write a debug line to stderr (won't interfere with stdout JSON)."""
    print(f"[music-backend] {msg}", file=sys.stderr, flush=True)


def resp(**kwargs) -> str:
    """Serialize a response dict to JSON + newline."""
    return json.dumps(kwargs, ensure_ascii=False) + "\n"


# ── Dependency checking ─────────────────────────────────────────────
def check_deps() -> dict:
    deps: dict[str, bool | str] = {}
    for name, cmd in [("python3", ["python3", "--version"]),
                       ("yt-dlp", ["yt-dlp", "--version"]),
                       ("ffmpeg", ["ffmpeg", "-version"])]:
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=5)
            if r.returncode == 0:
                out = r.stdout.decode("utf-8", errors="replace").strip().split("\n")[0]
                deps[name] = out
            else:
                deps[name] = False
        except (FileNotFoundError, subprocess.TimeoutExpired):
            deps[name] = False
    return deps


# ── Search ──────────────────────────────────────────────────────────
_search_proc: subprocess.Popen | None = None
_search_cancelled = threading.Event()

# Query → (timestamp, results). Repeat searches resolve instantly.
_search_cache: dict[str, tuple[float, list]] = {}
_search_cache_order: list[str] = []
SEARCH_CACHE_TTL = 600
SEARCH_CACHE_MAX = 50


def _cache_key(query: str) -> str:
    return re.sub(r"\s+", " ", query.strip().lower())


def _cache_get(key: str) -> list | None:
    hit = _search_cache.get(key)
    if not hit:
        return None
    ts, results = hit
    if time.monotonic() - ts > SEARCH_CACHE_TTL:
        _search_cache.pop(key, None)
        if key in _search_cache_order:
            _search_cache_order.remove(key)
        return None
    return results


def _cache_put(key: str, results: list) -> None:
    _search_cache[key] = (time.monotonic(), results)
    if key in _search_cache_order:
        _search_cache_order.remove(key)
    _search_cache_order.append(key)
    while len(_search_cache_order) > SEARCH_CACHE_MAX:
        _search_cache.pop(_search_cache_order.pop(0), None)


def _cancel_search() -> None:
    """Cancel any in-flight search."""
    global _search_proc
    _search_cancelled.set()
    if _search_proc and _search_proc.poll() is None:
        try:
            _search_proc.terminate()
            _search_proc.wait(timeout=3)
        except Exception:
            try:
                _search_proc.kill()
                _search_proc.wait(timeout=2)
            except Exception:
                pass
    _search_proc = None


def search(query: str, generation: int = 0) -> str:
    global _search_proc
    _cancel_search()
    _search_cancelled.clear()

    if not query or not query.strip():
        return resp(type="search_results", results=[], generation=generation)

    query = query.strip()
    if len(query) < 2:
        return resp(type="search_results", results=[],
                    error="Query too short", generation=generation)

    # Repeat queries resolve instantly from cache.
    key = _cache_key(query)
    cached = _cache_get(key)
    if cached is not None:
        return resp(type="search_results", results=cached,
                    generation=generation, cached=True)

    # Use yt-dlp flat playlist search with JSON output.
    # NOTE: bare `ytsearch` means "1 result" — the 12 is what fills the list.
    cmd = [
        "yt-dlp",
        "--default-search", "ytsearch12",
        "-j",  # flat JSON output (one line per result)
        "--flat-playlist",  # don't download, just extract info
        "--no-warnings",
        f"--playlist-end={MAX_RESULTS}",
        query,
    ]

    try:
        _search_proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            # yt-dlp buffers stdout when piped; unbuffer so result lines
            # stream to us (and the UI) as they are extracted.
            env={**os.environ, "PYTHONUNBUFFERED": "1"},
        )
    except FileNotFoundError as e:
        return resp(type="error", error=f"yt-dlp not found: {e}",
                    generation=generation)
    except Exception as e:
        return resp(type="error", error=str(e), generation=generation)

    results = []
    try:
        out = _search_proc.stdout
        if out is None:
            return resp(type="error", error="Search failed to start")
        for raw_line in iter(out.readline, b""):
            if _search_cancelled.is_set():
                return resp(type="search_cancelled", generation=generation)
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            duration = entry.get("duration") or entry.get("duration_string")
            dur_int = int(duration) if isinstance(duration, (int, float)) else 0

            # Pick best thumbnail
            thumbnails = entry.get("thumbnails") or []
            thumb_url = ""
            for t in reversed(thumbnails):
                if isinstance(t, dict) and t.get("url"):
                    pref = t.get("preference", -1)
                    if pref >= 0 or not thumb_url:
                        thumb_url = t["url"]

            artist = (entry.get("artist")
                      or entry.get("channel")
                      or entry.get("uploader")
                      or "Unknown Artist")

            results.append({
                "id": entry.get("id", ""),
                "title": entry.get("title", "Untitled"),
                "artist": artist,
                "duration": dur_int,
                "thumbnail": thumb_url,
                "webpage_url": entry.get("webpage_url", "") or entry.get("url", ""),
            })

            # Stream what we have so far: the UI paints the first hits
            # instead of waiting for the whole list.
            emit(resp(type="search_partial", results=results,
                      generation=generation))

            if len(results) >= MAX_RESULTS:
                break

        _search_proc.wait(timeout=10)
    except Exception as e:
        log(f"Search error: {e}")

    _search_proc = None
    if results:
        _cache_put(key, results)
    return resp(type="search_results", results=results,
                generation=generation)


# ── Resolve (get playable URL) ─────────────────────────────────────
_resolve_proc: subprocess.Popen | None = None


def resolve(url: str) -> str:
    global _resolve_proc
    # Kill any previous resolve
    if _resolve_proc and _resolve_proc.poll() is None:
        try:
            _resolve_proc.terminate()
            _resolve_proc.wait(timeout=5)
        except Exception:
            try:
                _resolve_proc.kill()
            except Exception:
                pass

    cmd = [
        "yt-dlp",
        "-f", "bestaudio[ext=m4a]/bestaudio/best",
        "--no-download",
        "--print", "url",
        url,
    ]

    try:
        _resolve_proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        stdout, stderr = _resolve_proc.communicate(timeout=30)
        if _resolve_proc.returncode == 0:
            play_url = stdout.decode("utf-8", errors="replace").strip()
            if play_url:
                return resp(type="resolved", url=play_url)
            return resp(type="error", error="No playable URL found")
        else:
            err = stderr.decode("utf-8", errors="replace").strip()[:200]
            return resp(type="error", error=f"Resolve failed: {err}")
    except FileNotFoundError:
        return resp(type="error", error="yt-dlp not found")
    except subprocess.TimeoutExpired:
        _resolve_proc.kill()
        return resp(type="error", error="Resolve timed out")
    except Exception as e:
        return resp(type="error", error=str(e))
    finally:
        _resolve_proc = None


# ── Download ────────────────────────────────────────────────────────
_download_proc: subprocess.Popen | None = None


def _sanitize_filename(name: str) -> str:
    """Replace characters unsafe for most filesystems."""
    name = re.sub(r'[\\/:*?"<>|]', '_', name).strip()
    name = re.sub(r'\s+', ' ', name)
    return name[:200] or "untitled"


def download(url: str, title: str, artist: str) -> str:
    global _download_proc

    if _download_proc and _download_proc.poll() is None:
        return resp(type="download_error",
                    error="A download is already in progress")

    MUSIC_DIR.mkdir(parents=True, exist_ok=True)

    safe_artist = _sanitize_filename(artist)
    safe_title = _sanitize_filename(title)
    artist_dir = MUSIC_DIR / safe_artist
    artist_dir.mkdir(parents=True, exist_ok=True)

    output_template = str(artist_dir / "%(title)s.%(ext)s")

    cmd = [
        "yt-dlp",
        "-f", "bestaudio[ext=m4a]/bestaudio/best",
        "-x",  # extract audio
        "--audio-format", "mp3",
        "--audio-quality", "192K",
        "-o", output_template,
        "--no-playlist",
        "--progress-template",
        '{"status":"downloading","percent":"%(progress.percent)s",'
        '"speed":"%(progress.speed)s","eta":"%(progress.eta)s"}',
        url,
    ]

    try:
        _download_proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        # Stream progress lines
        dout = _download_proc.stdout
        if dout is None:
            emit(resp(type="download_error",
                      error="Download failed to start"))
            return ""
        for line in iter(dout.readline, ""):
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            try:
                prog = json.loads(line)
                if prog.get("status") == "downloading":
                    pct = prog.get("percent", "0").strip().rstrip("%")
                    emit(resp(
                        type="download_progress",
                        percent=pct,
                        speed=prog.get("speed", ""),
                        eta=prog.get("eta", ""),
                        title=title,
                    ))
            except (json.JSONDecodeError, ValueError):
                # Non-JSON progress line from yt-dlp — ignore
                pass

        _download_proc.wait(timeout=300)  # 5 min max wait

        if _download_proc.returncode == 0:
            emit(resp(
                type="download_complete",
                title=title,
                artist=safe_artist,
                path=str(artist_dir / f"{safe_title}.mp3"),
            ))
        else:
            emit(resp(
                type="download_error",
                error=f"Download failed (exit {_download_proc.returncode})",
                title=title,
            ))

    except FileNotFoundError:
        emit(resp(type="download_error",
                  error="yt-dlp not installed"))
    except Exception as e:
        emit(resp(type="download_error", error=str(e)))
    finally:
        _download_proc = None

    return ""


# ── Library ─────────────────────────────────────────────────────────
SUPPORTED_EXTS = {".mp3", ".m4a", ".flac", ".ogg", ".wav", ".opus", ".wma"}


def library() -> str:
    tracks = []
    if not MUSIC_DIR.exists():
        return resp(type="library", tracks=[])

    for ext in SUPPORTED_EXTS:
        for fpath in sorted(MUSIC_DIR.rglob(f"*{ext}"), key=lambda p: p.stat().st_mtime, reverse=True):
            stat = fpath.stat()
            rel = fpath.relative_to(MUSIC_DIR)
            parts = rel.parts
            artist = parts[0] if len(parts) > 1 else "Unknown"
            title = fpath.stem
            tracks.append({
                "title": title,
                "artist": artist,
                "path": str(fpath),
                "size": stat.st_size,
                "modified": stat.st_mtime,
            })

    return resp(type="library", tracks=tracks[:100])  # cap at 100


# ── Thread-safe stdout ───────────────────────────────────────────────
# The MPRIS GLib thread and the main stdin loop both write JSON lines.
_stdout_lock = threading.Lock()


def emit(line: str) -> None:
    """Write one JSON line to stdout without interleaving."""
    with _stdout_lock:
        sys.stdout.write(line)
        sys.stdout.flush()


# ── MPRIS (dashboard media + lyrics integration) ─────────────────────
try:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    HAVE_MPRIS = True
    _mpris_import_error = ""
except Exception as _mpris_err:  # dbus/gi missing: run without MPRIS
    HAVE_MPRIS = False
    _mpris_import_error = str(_mpris_err)

_MPRIS_BUS_NAME = "org.mpris.MediaPlayer2.caelestia"
_MPRIS_PATH = "/org/mpris/MediaPlayer2"
_MPRIS_ROOT = "org.mpris.MediaPlayer2"
_MPRIS_PLAYER = "org.mpris.MediaPlayer2.Player"
_MPRIS_PROPS = "org.freedesktop.DBus.Properties"


class _MprisState:
    def __init__(self):
        self.status = "Stopped"
        self.title = ""
        self.artist = ""
        self.art_url = ""
        self.track_url = ""
        self.length_us = 0
        self.pos_us = 0
        self.pos_mono = time.monotonic()
        self.volume = 0.8
        self.serial = -1
        self.can_next = False
        self.can_prev = False

    def snapshot(self, data: dict) -> None:
        self.status = data.get("status", "Stopped")
        self.title = data.get("title", "") or ""
        self.artist = data.get("artist", "") or ""
        self.art_url = data.get("art_url", "") or ""
        self.track_url = data.get("url", "") or ""
        try:
            self.length_us = max(0, int(data.get("length_us", 0) or 0))
        except (TypeError, ValueError):
            self.length_us = 0
        try:
            self.pos_us = max(0, int(data.get("position_us", 0) or 0))
        except (TypeError, ValueError):
            self.pos_us = 0
        self.pos_mono = time.monotonic()
        try:
            self.volume = min(1.0, max(0.0, float(data.get("volume", 0.8))))
        except (TypeError, ValueError):
            pass
        try:
            self.serial = int(data.get("serial", self.serial))
        except (TypeError, ValueError):
            pass
        self.can_next = bool(data.get("can_next", False))
        self.can_prev = bool(data.get("can_prev", False))

    def position_now(self) -> int:
        if self.status == "Playing":
            return self.pos_us + int((time.monotonic() - self.pos_mono) * 1e6)
        return self.pos_us


if HAVE_MPRIS:
    class _MprisService(dbus.service.Object):
        def __init__(self, bus, state: _MprisState):
            super().__init__(bus, _MPRIS_PATH)
            self._st = state

        @dbus.service.signal(_MPRIS_PROPS, signature="sa{sv}as")
        def PropertiesChanged(self, interface, changed, invalidated):
            pass

        @dbus.service.signal(_MPRIS_PLAYER, signature="x")
        def Seeked(self, position):
            pass

        def _changed(self, changed: dict) -> None:
            self.PropertiesChanged(_MPRIS_PLAYER, changed, [])

        # -- metadata ------------------------------------------------
        def _metadata(self) -> dbus.Dictionary:
            st = self._st
            md = {
                "mpris:trackid": dbus.ObjectPath(
                    f"/org/mpris/MediaPlayer2/Track/{max(st.serial, 0)}"),
                "xesam:title": dbus.String(st.title or "Unknown"),
            }
            if st.artist:
                md["xesam:artist"] = dbus.Array([dbus.String(st.artist)],
                                                signature="s")
            if st.track_url:
                md["xesam:url"] = dbus.String(st.track_url)
            if st.art_url:
                md["mpris:artUrl"] = dbus.String(st.art_url)
            if st.length_us > 0:
                md["mpris:length"] = dbus.Int64(st.length_us)
            return dbus.Dictionary(md, signature="sv")

        # -- org.freedesktop.DBus.Properties -------------------------
        @dbus.service.method(_MPRIS_PROPS, in_signature="ss",
                             out_signature="v")
        def Get(self, interface, prop):
            return self._get_all(interface)[prop]

        @dbus.service.method(_MPRIS_PROPS, in_signature="s",
                             out_signature="a{sv}")
        def GetAll(self, interface):
            return self._get_all(interface)

        @dbus.service.method(_MPRIS_PROPS, in_signature="ssv")
        def Set(self, interface, prop, value):
            if interface == _MPRIS_PLAYER and prop == "Volume":
                try:
                    emit(resp(type="mpris_command", command="volume",
                              value=float(value)))
                except (TypeError, ValueError):
                    pass

        def _get_all(self, interface):
            st = self._st
            if interface == _MPRIS_ROOT:
                return {
                    "Identity": dbus.String("Caelestia Music"),
                    "CanQuit": dbus.Boolean(False),
                    "CanRaise": dbus.Boolean(False),
                    "CanSetFullscreen": dbus.Boolean(False),
                    "HasTrackList": dbus.Boolean(False),
                    "SupportedUriSchemes": dbus.Array(
                        ["file", "http", "https"], signature="s"),
                    "SupportedMimeTypes": dbus.Array(
                        ["audio/mpeg", "audio/mp4", "audio/x-flac",
                         "audio/ogg", "audio/opus", "audio/x-wav"],
                        signature="s"),
                }
            if interface == _MPRIS_PLAYER:
                return {
                    "PlaybackStatus": dbus.String(st.status),
                    "LoopStatus": dbus.String("None"),
                    "Rate": dbus.Double(1.0),
                    "Shuffle": dbus.Boolean(False),
                    "Metadata": self._metadata(),
                    "Volume": dbus.Double(st.volume),
                    "Position": dbus.Int64(st.position_now()),
                    "MinimumRate": dbus.Double(1.0),
                    "MaximumRate": dbus.Double(1.0),
                    "CanGoNext": dbus.Boolean(st.can_next),
                    "CanGoPrevious": dbus.Boolean(st.can_prev),
                    "CanPlay": dbus.Boolean(True),
                    "CanPause": dbus.Boolean(True),
                    "CanSeek": dbus.Boolean(st.length_us > 0),
                    "CanControl": dbus.Boolean(True),
                }
            return {}

        # -- transport methods (forwarded to QML) --------------------
        def _cmd(self, command: str, **extra) -> None:
            emit(resp(type="mpris_command", command=command, **extra))

        @dbus.service.method(_MPRIS_PLAYER)
        def Play(self):
            self._cmd("play")

        @dbus.service.method(_MPRIS_PLAYER)
        def Pause(self):
            self._cmd("pause")

        @dbus.service.method(_MPRIS_PLAYER)
        def PlayPause(self):
            self._cmd("toggle")

        @dbus.service.method(_MPRIS_PLAYER)
        def Stop(self):
            self._cmd("stop")

        @dbus.service.method(_MPRIS_PLAYER)
        def Next(self):
            self._cmd("next")

        @dbus.service.method(_MPRIS_PLAYER)
        def Previous(self):
            self._cmd("previous")

        @dbus.service.method(_MPRIS_PLAYER, in_signature="x")
        def Seek(self, offset_us):
            self._cmd("seek", offset_us=int(offset_us))

        @dbus.service.method(_MPRIS_PLAYER, in_signature="ox")
        def SetPosition(self, _track_id, position_us):
            self._cmd("position", position_us=int(position_us))

        @dbus.service.method(_MPRIS_PLAYER, in_signature="s")
        def OpenUri(self, _uri):
            pass

        def apply_update(self, data: dict) -> None:
            st = self._st
            old_status = st.status
            old_serial = st.serial
            old_volume = st.volume
            old_can_next = st.can_next
            old_can_prev = st.can_prev
            st.snapshot(data)
            changed = {}
            if st.status != old_status:
                changed["PlaybackStatus"] = dbus.String(st.status)
            if st.serial != old_serial:
                changed["Metadata"] = self._metadata()
            if abs(st.volume - old_volume) > 1e-6:
                changed["Volume"] = dbus.Double(st.volume)
            if st.can_next != old_can_next:
                changed["CanGoNext"] = dbus.Boolean(st.can_next)
            if st.can_prev != old_can_prev:
                changed["CanGoPrevious"] = dbus.Boolean(st.can_prev)
            if changed:
                self._changed(changed)
            self.Seeked(dbus.Int64(st.position_now()))


    _mpris_state = _MprisState()
    _mpris_queue: _queue.Queue = _queue.Queue()
    _mpris_service: _MprisService | None = None

    def _mpris_drain():
        try:
            while True:
                data = _mpris_queue.get_nowait()
                if _mpris_service is not None:
                    _mpris_service.apply_update(data)
        except _queue.Empty:
            pass
        return True  # keep the timeout source alive

    def start_mpris() -> None:
        global _mpris_service
        try:
            DBusGMainLoop(set_as_default=True)
            bus = dbus.SessionBus()
            bus.request_name(_MPRIS_BUS_NAME)
            _mpris_service = _MprisService(bus, _mpris_state)
            GLib.timeout_add(100, _mpris_drain)
            t = threading.Thread(target=GLib.MainLoop().run,
                                 name="mpris", daemon=True)
            t.start()
            log(f"MPRIS server started as {_MPRIS_BUS_NAME}")
        except Exception as e:
            log(f"MPRIS failed to start: {e}")
else:
    def start_mpris() -> None:
        log(f"MPRIS disabled (dbus/gi unavailable: {_mpris_import_error})")


# ── Main loop ───────────────────────────────────────────────────────
def _on_sigterm(_signum, _frame):
    sys.exit(0)


signal.signal(signal.SIGTERM, _on_sigterm)
signal.signal(signal.SIGINT, _on_sigterm)

# Buffer stdout line-buffered so QML reads complete JSON lines
sys.stdout.reconfigure(line_buffering=True)

log("Music backend started")
start_mpris()

try:
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            cmd = json.loads(line)
        except json.JSONDecodeError:
            emit(resp(type="error", error="Invalid JSON"))
            continue

        action = cmd.get("action", "")

        if action == "search":
            emit(search(cmd.get("query", ""),
                        int(cmd.get("generation", 0) or 0)))
        elif action == "resolve":
            emit(resolve(cmd.get("url", "")))
        elif action == "download":
            emit(download(
                cmd.get("url", ""),
                cmd.get("title", "Unknown"),
                cmd.get("artist", "Unknown"),
            ))
        elif action == "library":
            emit(library())
        elif action == "check_deps":
            deps = check_deps()
            missing = [k for k, v in deps.items() if v is False]
            emit(resp(type="deps", deps=deps, missing=missing))
        elif action == "mpris_state":
            if HAVE_MPRIS:
                _mpris_queue.put(cmd)
        else:
            emit(resp(type="error", error=f"Unknown action: {action}"))

except EOFError:
    pass
finally:
    _cancel_search()
    if _resolve_proc and _resolve_proc.poll() is None:
        _resolve_proc.terminate()
    if _download_proc and _download_proc.poll() is None:
        _download_proc.terminate()

log("Music backend exiting")
