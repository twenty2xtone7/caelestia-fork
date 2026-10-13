# Caelestia

A QuickShell configuration providing a customizable desktop shell experience.

## Features

- **Drawers** - Configurable panel drawers for system information and controls
- **Launcher** - Application launcher with command registry and search capabilities
- **Radial Menu** - Contextual radial menu system
- **Area Picker** - Region selection and screenshot tools
- **Lock Screen** - Secure desktop lock with idle monitoring
- **Background Manager** - Dynamic wallpaper and background controls

## Architecture

The project is organized into modular components:

```
├── shell.qml          # Main entry point
├── modules/          # Feature modules
│   ├── drawers/      # Panel drawer system
│   ├── launcher/     # Application launcher
│   ├── radial/       # Radial menu
│   ├── areapicker/   # Area selection
│   ├── lock/         # Lock screen
│   └── background/   # Background management
├── components/       # Reusable UI components
├── services/         # Core services (GSFLoader, ServiceLoader)
├── utils/            # Utility functions
├── i18n/             # Internationalization files
├── tools/            # Development tools
└── assets/           # Static assets
```

## Requirements

- [QuickShell](https://quickshell.org/)
- [Hyprland](https://hyprwm.github.io/) (or compatible Wayland compositor)
- [Qt 6](https://qt.io/)

## Installation

```bash
# 1. Install QuickShell if not already present
# 2. Copy the caelestia folder to ~/.config/quickshell/
cp -r caelestia ~/.config/quickshell/

# 3. Start QuickShell pointing to this config
qs ~/.config/quickshell/caelestia/shell.qml
```

## Configuration

Edit the QML files in `modules/` to customize behavior. Each module is self-contained and can be enabled/disabled in `shell.qml`.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
