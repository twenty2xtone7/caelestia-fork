#!/usr/bin/env python3
"""Map a desktop-entry id to something this user can uninstall.

Stdout is one line, a tab-separated record:

    kind<TAB>target<TAB>detail<TAB>extra

kind is one of:
    pacman         target is a package name, detail is "name version"
    aur            same, but the package is not in the sync DBs
    flatpak-user   target is an application id, detail is the app name
    flatpak-system same, but installed system-wide (needs polkit)
    prefix-game    Wine/Proton game launched through flatpak. target is the
                   .desktop path, detail is the game name, extra is
                   "trash:<game dir>" (both trashed: entry + game folder)
    home-binary    manually installed program under $HOME. target is the
                   .desktop path, detail is the app label, extra is
                   "trash:<binary path>" (both trashed: entry + binary)
    user           target is the desktop file path (not a system package).
                   Only the launcher entry is removed. extra may be
                   "bin:<path>|<owner>" info for display.
    system-entry   unattributed system launcher file (stale entry, missing
                   program). target is the file; removal deletes just that
                   file via polkit, never program files.
    none           nothing uninstallable was found (detail may be "protected"
                   or "manual:<path>").

Only user-owned files are ever offered for trashing. System binaries and
package files are never deleted directly: they go through pacman, or are
reported for manual removal.

Never prints a shell command. The caller builds argv itself.
"""

import os
import re
import shlex
import shutil
import subprocess
import sys

XDG_DATA_DIRS = [
    os.path.expanduser("~/.local/share"),
    "/usr/local/share",
    "/usr/share",
    os.path.expanduser("~/.local/share/flatpak/exports/share"),
    "/var/lib/flatpak/exports/share",
]

HOME = os.path.expanduser("~")
LOCAL_APPS = os.path.join(HOME, ".local", "share", "applications")

# Packages that must not be removed from a launcher click.
PROTECTED = {
    "base",
    "base-devel",
    "linux",
    "linux-lts",
    "linux-zen",
    "linux-hardened",
    "linux-headers",
    "systemd",
    "systemd-libs",
    "pacman",
    "filesystem",
    "glibc",
    "bash",
    "coreutils",
    "sudo",
    "hyprland",
    "quickshell",
    "caelestia-shell",
    "flatpak",
}


def desktop_paths(entry_id: str):
    """Find .desktop files for a quickshell entry id.

    Scans the applications dirs and recomputes each file's id the way
    quickshell does (relative dir joined with '-', plus basename), because
    splitting the id on '-' is ambiguous when basenames contain dashes
    (e.g. screensavers/xfce-floaters.desktop -> screensavers-xfce-floaters).
    """
    wanted_leaf = entry_id + ".desktop"
    seen = set()
    for root in XDG_DATA_DIRS:
        apps = os.path.join(root, "applications")
        if not os.path.isdir(apps):
            continue
        for dirpath, _dirnames, filenames in os.walk(apps):
            for fn in filenames:
                if not fn.endswith(".desktop"):
                    continue
                path = os.path.join(dirpath, fn)
                if path in seen or not os.path.isfile(path):
                    continue
                seen.add(path)
                rel = os.path.relpath(path, apps)
                qid = rel[:-8].replace(os.sep, "-") if rel.endswith(".desktop") else None
                if qid == entry_id or fn == wanted_leaf:
                    yield path


def run(argv):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=8)
    except (OSError, subprocess.TimeoutExpired):
        return 1, "", ""
    return proc.returncode, proc.stdout, proc.stderr


def emit(kind, target="", detail="", extra=""):
    print(f"{kind}\t{target}\t{detail}\t{extra}")


def under_home(path: str) -> bool:
    return path == HOME or path.startswith(HOME + os.sep)


def read_key(path: str, key: str):
    """Raw value of key= in the [Desktop Entry] group, or None."""
    prefix = key + "="
    try:
        with open(path, encoding="utf-8-sig", errors="replace") as f:
            in_entry = False
            for line in f:
                line = line.rstrip("\n")
                if line.startswith("["):
                    in_entry = line.strip().lower() == "[desktop entry]"
                    continue
                if in_entry and line.startswith(prefix):
                    return line[len(prefix):].strip()
    except OSError:
        return None
    return None


def parse_exec(exec_line: str):
    """Split an Exec line into argv, dropping freedesktop %codes."""
    try:
        argv = shlex.split(exec_line, posix=True)
    except ValueError:
        return []
    # Drop a lone trailing %code; also strip codes glued to other text is
    # unsafe, so only drop standalone tokens starting with %.
    return [a for a in argv if not (a.startswith("%") and len(a) == 2)]


def resolve_binary(argv0: str):
    """Locate the program for an argv[0]: absolute path or $PATH lookup."""
    if not argv0:
        return None
    if os.sep in argv0:
        return argv0 if os.path.exists(argv0) else None
    return shutil.which(argv0)


def skip_wrappers(argv):
    """Skip env(1) and VAR= assignments to find the real program."""
    i = 0
    if i < len(argv) and os.path.basename(argv[0]) == "env":
        i += 1
    while i < len(argv) and "=" in argv[i] and not argv[i].startswith("-") \
            and os.sep not in argv[i]:
        key, _, _ = argv[i].partition("=")
        if key and key.replace("_", "").isalnum():
            i += 1
        else:
            break
    return argv[i:] if i < len(argv) else []


def flatpak_for(path: str):
    # .../exports/share/applications/<appid>.desktop
    if "flatpak" not in path or not path.endswith(".desktop"):
        return None
    appid = os.path.splitext(os.path.basename(path))[0]
    if "." not in appid:
        return None
    code, _, _ = run(["flatpak", "info", "--show-commit", appid])
    if code != 0:
        return None
    scope = "user" if under_home(path) else "system"
    return appid, flatpak_name(appid), scope


def pacman_owner(path: str):
    code, out, err = run(["pacman", "-Qo", path])
    text = (out or err).strip()
    # "/path is owned by name version"
    marker = " is owned by "
    if code != 0 or marker not in text:
        return None
    rest = text.split(marker, 1)[1].strip()
    parts = rest.split()
    if not parts:
        return None
    name = parts[0]
    version = parts[1] if len(parts) > 1 else ""
    if name in PROTECTED:
        return ("protected", name, version)
    code, _, _ = run(["pacman", "-Si", name])
    kind = "pacman" if code == 0 else "aur"
    return (kind, name, version)


def flatpak_name(appid: str) -> str:
    code, name_out, _ = run(["flatpak", "info", appid])
    if code != 0:
        return appid
    # `flatpak info` header is "<Name> - <summary>" on the first non-empty line.
    first = next((l for l in name_out.splitlines() if l.strip()), "")
    if " - " in first:
        return first.split(" - ", 1)[0].strip() or appid
    return appid


def exe_payload(argv):
    """Split `flatpak run [flags] <appid> ...` into (appid, exe-or-None).

    Flags may sit between `run` and the app id (flatpak export launchers
    always pass --branch/--arch). The .exe search covers Wine-game shortcuts.
    """
    if len(argv) >= 3 and os.path.basename(argv[0]) == "flatpak" and argv[1] == "run":
        rest = argv[2:]
        appid = next((a for a in rest if not a.startswith("-") and "." in a), None)
        if not appid:
            return None, None
        for arg in rest:
            if arg.lower().endswith(".exe") and os.sep in arg:
                return appid, arg
        return appid, None
    return None, None


SHELLS = {"sh", "bash", "dash", "zsh", "fish", "ksh"}


def unwrap_shell(argv):
    """Unwrap `sh -c '<cmd>...'` (BlackArch menu style) to the inner argv."""
    if not argv or os.path.basename(argv[0]) not in SHELLS:
        return argv
    try:
        inner = argv[argv.index("-c") + 1]
    except (ValueError, IndexError):
        return []
    chunk = re.split(r"&&|\|\||;", inner)[0]
    try:
        return shlex.split(chunk, posix=True)
    except ValueError:
        return []


def desktop_stripped(path: str) -> str:
    """Desktop basename minus extension and generator prefixes (e.g. ba-)."""
    base = os.path.splitext(os.path.basename(path))[0]
    for prefix in ("ba-",):
        if base.startswith(prefix):
            return base[len(prefix):]
    return base


def names_relate(a: str, b: str) -> bool:
    return bool(a) and bool(b) and (a == b or a in b or b in a)


def pkg_installed(name: str):
    """Exact-name lookup in the local pacman DB (any origin)."""
    code, out, _ = run(["pacman", "-Q", name])
    if code != 0 or not out.strip():
        return None
    parts = out.strip().split()
    if not parts:
        return None
    iname = parts[0]
    version = parts[1] if len(parts) > 1 else ""
    if iname in PROTECTED:
        return ("protected", iname, version)
    code, _, _ = run(["pacman", "-Si", iname])
    return (("pacman" if code == 0 else "aur"), iname, version)


def packaged_offer(desktop_path: str, binary: str, pkg: str) -> bool:
    """Is removing `pkg` a sane uninstall for this loose system launcher?

    Requires the binary name and the launcher name to both relate to the
    package name, so a custom shortcut to a generic runtime (python,
    xdg-open, wine, …) never offers to remove that runtime.
    """
    if under_home(desktop_path):
        return False
    bin_base = os.path.basename(binary)
    stripped = desktop_stripped(desktop_path)
    return names_relate(bin_base, pkg) and (
        names_relate(stripped, pkg) or names_relate(stripped, bin_base))


def main():
    if len(sys.argv) != 2 or not sys.argv[1].strip():
        emit("none")
        return 0
    entry_id = sys.argv[1].strip()
    # Ids are desktop basenames (spaces allowed); reject path tricks and
    # shell metacharacters. Safe anyway: used as argv, never a shell.
    if "/" in entry_id or "\\" in entry_id or "\x00" in entry_id \
            or not all(c.isalnum() or c in " ._-+@" for c in entry_id):
        emit("none")
        return 0

    paths = list(desktop_paths(entry_id))
    if not paths:
        emit("none")
        return 0

    for path in paths:
        fp = flatpak_for(path)
        if fp:
            appid, name, scope = fp
            emit(f"flatpak-{scope}", appid, name)
            return 0

    for path in paths:
        owned = pacman_owner(path)
        if not owned:
            continue
        kind, name, version = owned
        if kind == "protected":
            emit("none", name, "protected")
            return 0
        emit(kind, name, f"{name} {version}".strip())
        return 0

    # No package owns the .desktop: look at what it actually runs.
    manual = None  # (desktop, binary, owner) for the manual-remove fallback
    for path in paths:
        exec_line = read_key(path, "Exec")
        argv = unwrap_shell(skip_wrappers(parse_exec(exec_line))) if exec_line else []
        if not argv:
            # TryExec has no arguments by spec; use it as a bare program.
            te = read_key(path, "TryExec")
            argv = [te] if te else []
        if not argv:
            continue

        # Flatpak runner: a Windows .exe arg means a Wine/Proton game
        # (entry + game folder, both user-owned). A bare app id with flags
        # is a normal flatpak launcher spelling.
        runner, exe = exe_payload(argv)
        if runner and not exe:
            code, _, _ = run(["flatpak", "info", "--show-commit", runner])
            if code == 0:
                scope = "user" if under_home(path) else "system"
                emit(f"flatpak-{scope}", runner, flatpak_name(runner))
                return 0
        if exe and under_home(path):
            game_dir = os.path.dirname(exe)
            if game_dir and under_home(game_dir) and os.path.isdir(game_dir):
                game = os.path.splitext(os.path.basename(exe))[0]
                emit("prefix-game", path, game or os.path.basename(path),
                     f"trash:{game_dir}")
                return 0

        binary = resolve_binary(argv[0])
        if not (binary and os.path.isfile(binary)):
            continue
        owner = pacman_owner(binary)
        if not owner:
            # Unowned binary: only the launcher entry is removed. The
            # binary stays (user may want it). Shown as display-only info.
            if under_home(path):
                emit("user", path, os.path.basename(path),
                     f"bin:{binary}|unmanaged")
                return 0
            manual = manual or (path, binary, "")
            continue
        kind2, pkg, ver = owner
        if kind2 == "protected":
            if under_home(path):
                emit("user", path, os.path.basename(path),
                     f"bin:{binary}|protected:{pkg}")
                return 0
            manual = manual or (path, binary, f"protected:{pkg}")
            continue
        # Packaged binary behind a loose launcher.
        if under_home(path):
            # User-local file: likely a custom shortcut, so only the entry
            # is removed; the package name is shown for transparency.
            emit("user", path, os.path.basename(path),
                 f"bin:{binary}|{kind2}:{pkg}")
            return 0
        if packaged_offer(path, binary, pkg):
            # System-wide launcher whose program is that package: remove
            # the package, then the leftover loose launcher file.
            emit(kind2, pkg, f"{pkg} {ver}".strip(), f"rm:{path}")
            return 0
        manual = manual or (path, binary, f"{kind2}:{pkg}")

    # Loose system launcher whose name is an installed package (e.g. a
    # BlackArch menu file pointing at a helper that no longer exists):
    # offer the package plus leftover-file cleanup. Exact name match only.
    for path in paths:
        if under_home(path):
            continue
        hit = pkg_installed(desktop_stripped(path))
        if hit and hit[0] != "protected":
            kind2, pkg, ver = hit
            emit(kind2, pkg, f"{pkg} {ver}".strip(), f"rm:{path}")
            return 0

    # Local .desktop with nothing resolvable behind it: entry only.
    for path in paths:
        if under_home(path) and path.startswith(LOCAL_APPS + os.sep):
            emit("user", path, os.path.basename(path))
            return 0

    if manual:
        path, binary, owner = manual
        emit("none", "", f"manual:{path}", f"bin:{binary}|{owner}")
        return 0

    # Unattributed system launcher file with nothing resolvable behind it
    # (stale entry, missing program). Removing the file only drops a menu
    # entry, never program files, so offer it with an explicit confirm.
    # Recheck ownership first: a transient pacman failure must not turn a
    # packaged file into a direct delete.
    for path in paths:
        if under_home(path) or pacman_owner(path):
            continue
        emit("system-entry", path, os.path.basename(path))
        return 0

    emit("none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
