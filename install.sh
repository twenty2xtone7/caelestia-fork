#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_CAELESTIA="${SCRIPT_DIR}"
CUSTOM_HYPR="${SCRIPT_DIR}/hypr"

DEST_CAELESTIA="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
DEST_HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

BACKUP_CAELESTIA=""
BACKUP_HYPR=""

log()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
  elif [[ -f /etc/NIXOS ]]; then
    DISTRO_ID="nixos"
    DISTRO_LIKE=""
  else
    DISTRO_ID="unknown"
    DISTRO_LIKE=""
  fi
  log "Detected distribution: $DISTRO_ID"
}

install_package() {
  detect_distro

  local installed=0

  if [[ "$DISTRO_ID" =~ ^(arch|manjaro|endeavouros|blackarch|garuda|artix)$ ]] || \
     [[ "$DISTRO_LIKE" == *arch* ]]; then
    if command -v yay >/dev/null 2>&1; then
      log "Installing caelestia-shell via yay..."
      yay -S --needed caelestia-shell && installed=1
    elif command -v paru >/dev/null 2>&1; then
      log "Installing caelestia-shell via paru..."
      paru -S --needed caelestia-shell && installed=1
    elif command -v pacman >/dev/null 2>&1; then
      log "caelestia-shell is an AUR package. Install yay or paru first, or build from source."
      warn "Falling back to source build."
    fi

  elif [[ "$DISTRO_ID" == "nixos" ]] || command -v nix >/dev/null 2>&1; then
    log "NixOS / Nix detected. Installing Caelestia Shell via flake..."
    nix profile install github:caelestia-dots/shell#with-cli && installed=1

  elif [[ "$DISTRO_ID" =~ ^(fedora|rhel|centos|rocky|alma)$ ]] || \
       [[ "$DISTRO_LIKE" == *fedora* ]] || [[ "$DISTRO_LIKE" == *rhel* ]]; then
    if command -v dnf >/dev/null 2>&1; then
      log "caelestia-shell is not packaged for Fedora/RHEL."
      warn "Falling back to source build."
    fi

  elif [[ "$DISTRO_ID" =~ ^(debian|ubuntu|pop|linuxmint|elementary|zorin)$ ]] || \
       [[ "$DISTRO_LIKE" == *debian* ]] || [[ "$DISTRO_LIKE" == *ubuntu* ]]; then
    log "caelestia-shell is not packaged for Debian/Ubuntu."
    warn "Falling back to source build."

  elif [[ "$DISTRO_ID" =~ ^(opensuse|sles)$ ]] || [[ "$DISTRO_LIKE" == *suse* ]]; then
    log "caelestia-shell is not packaged for openSUSE."
    warn "Falling back to source build."

  elif [[ "$DISTRO_ID" == "void" ]]; then
    log "caelestia-shell is not packaged for Void Linux."
    warn "Falling back to source build."

  elif [[ "$DISTRO_ID" == "alpine" ]]; then
    log "caelestia-shell is not packaged for Alpine."
    warn "Falling back to source build."

  elif [[ "$DISTRO_ID" == "gentoo" ]]; then
    log "caelestia-shell is not packaged for Gentoo."
    warn "Falling back to source build."

  else
    warn "Unknown distribution: $DISTRO_ID"
    warn "Falling back to source build."
  fi

  if [[ "$installed" -eq 0 ]]; then
    build_from_source
  fi

  if ! command -v qs >/dev/null 2>&1 && ! command -v quickshell >/dev/null 2>&1; then
    die "Quickshell/Caelestia was not installed successfully. Check the output above."
  fi
  log "Caelestia Shell is available."
}

build_from_source() {
  log "Building Caelestia Shell from source..."
  local build_dir
  build_dir="$(mktemp -d)"
  trap 'rm -rf "$build_dir"' EXIT

  if ! command -v git >/dev/null 2>&1; then
    die "git is required to build from source. Install git and re-run."
  fi
  if ! command -v cmake >/dev/null 2>&1; then
    die "cmake is required to build from source. Install cmake and re-run."
  fi

  log "Cloning quickshell..."
  git clone --depth 1 https://github.com/quickshell-mirror/quickshell.git "$build_dir/quickshell"
  cmake -B "$build_dir/quickshell/build" -S "$build_dir/quickshell" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$build_dir/quickshell/build" -j"$(nproc)"
  sudo cmake --install "$build_dir/quickshell/build"

  log "Quickshell installed from source."
  log "Note: caelestia-cli (Python) must be installed separately if needed."
  log "  pip install --user caelestia"
}

validate_caelestia() {
  log "Validating custom Caelestia configuration..."

  if [[ ! -d "$CUSTOM_CAELESTIA" ]]; then
    die "Custom config directory not found: $CUSTOM_CAELESTIA"
  fi

  if [[ ! -f "$CUSTOM_CAELESTIA/shell.qml" ]]; then
    die "Custom config is incomplete (missing shell.qml): $CUSTOM_CAELESTIA"
  fi

  log "Custom config looks valid: $CUSTOM_CAELESTIA"
}

apply_caelestia() {
  log "Applying custom Caelestia configuration..."
  log "  Source:      $CUSTOM_CAELESTIA"
  log "  Destination: $DEST_CAELESTIA"

  if [[ "$(cd "$CUSTOM_CAELESTIA" && pwd)" == "$(cd "$DEST_CAELESTIA" 2>/dev/null && pwd)" ]]; then
    log "Source and destination are the same directory; skipping copy."
    return
  fi

  local parent
  parent="$(dirname "$DEST_CAELESTIA")"
  mkdir -p "$parent"

  if [[ -e "$DEST_CAELESTIA" ]]; then
    BACKUP_CAELESTIA="${DEST_CAELESTIA}.bak.$(date +%Y%m%d-%H%M%S)"
    log "Backing up existing config to: $BACKUP_CAELESTIA"
    if ! mv "$DEST_CAELESTIA" "$BACKUP_CAELESTIA"; then
      die "Failed to back up existing config. Aborting."
    fi
  fi

  mkdir -p "$DEST_CAELESTIA"
  rsync -a \
    --exclude='.git' \
    --exclude='hypr' \
    --exclude='*.bak*' \
    --exclude='*.backup*' \
    "$CUSTOM_CAELESTIA/" "$DEST_CAELESTIA/"

  chown -R "$(id -u):$(id -g)" "$DEST_CAELESTIA" 2>/dev/null || true

  if [[ ! -f "$DEST_CAELESTIA/shell.qml" ]]; then
    err "Verification failed: shell.qml missing after copy."
    if [[ -n "$BACKUP_CAELESTIA" && -d "$BACKUP_CAELESTIA" ]]; then
      warn "Restoring previous config..."
      rm -rf "$DEST_CAELESTIA"
      mv "$BACKUP_CAELESTIA" "$DEST_CAELESTIA"
    fi
    die "Custom config was not applied correctly."
  fi

  log "Custom Caelestia config applied."
  if [[ -n "$BACKUP_CAELESTIA" ]]; then
    log "  Backup: $BACKUP_CAELESTIA"
  fi
}

hyprland_available() {
  [[ -d "$CUSTOM_HYPR" ]] && [[ -n "$(ls -A "$CUSTOM_HYPR" 2>/dev/null)" ]]
}

ask_hyprland() {
  if ! hyprland_available; then
    warn "No custom Hyprland configuration found at: $CUSTOM_HYPR"
    warn "Skipping Hyprland configuration. Your existing Hyprland config is untouched."
    return 1
  fi

  echo
  echo "Custom Hyprland configuration is available."
  echo "  A) Install custom Hyprland config (existing config will be backed up)"
  echo "  B) Keep existing Hyprland config (no changes)"
  echo
  local choice
  read -r -p "Choose [A/B] (default B): " choice
  choice="${choice:-B}"
  case "$choice" in
    [Aa]) return 0 ;;
    *)    return 1 ;;
  esac
}

apply_hyprland() {
  log "Applying custom Hyprland configuration..."
  log "  Source:      $CUSTOM_HYPR"
  log "  Destination: $DEST_HYPR"

  if [[ ! -d "$CUSTOM_HYPR" ]]; then
    die "Custom Hyprland directory disappeared: $CUSTOM_HYPR"
  fi

  mkdir -p "$(dirname "$DEST_HYPR")"

  if [[ -e "$DEST_HYPR" ]]; then
    BACKUP_HYPR="${DEST_HYPR}.backup-$(date +%Y%m%d-%H%M%S)"
    log "Backing up existing Hyprland config to: $BACKUP_HYPR"
    if ! cp -a "$DEST_HYPR" "$BACKUP_HYPR"; then
      die "Failed to back up Hyprland config. Aborting Hyprland changes."
    fi
  fi

  if ! cp -a "$CUSTOM_HYPR"/. "$DEST_HYPR"/; then
    err "Failed to copy Hyprland config."
    if [[ -n "$BACKUP_HYPR" && -d "$BACKUP_HYPR" ]]; then
      warn "Restoring previous Hyprland config from backup..."
      rm -rf "$DEST_HYPR"
      mv "$BACKUP_HYPR" "$DEST_HYPR"
    fi
    die "Hyprland configuration was not applied."
  fi

  chown -R "$(id -u):$(id -g)" "$DEST_HYPR" 2>/dev/null || true
  log "Custom Hyprland config applied."
  log "  Backup: $BACKUP_HYPR"
}

main() {
  log "Caelestia installer"
  log "Script directory: $SCRIPT_DIR"
  echo

  check_prereqs
  echo

  install_package
  echo

  validate_caelestia
  apply_caelestia
  echo

  if ask_hyprland; then
    echo
    apply_hyprland
  else
    log "Hyprland configuration left unchanged."
  fi

  echo
  log "============================================================"
  log " Installation complete"
  log "============================================================"
  log " Caelestia config: $DEST_CAELESTIA"
  if [[ -n "$BACKUP_CAELESTIA" ]]; then
    log " Caelestia backup: $BACKUP_CAELESTIA"
  fi
  if [[ -n "$BACKUP_HYPR" ]]; then
    log " Hyprland backup:  $BACKUP_HYPR"
  else
    log " Hyprland config:  unchanged"
  fi
  log ""
  log " Start Caelestia with:  qs -c caelestia"
  log " Or:                     caelestia shell -d"
  log "============================================================"
}

main "$@"
