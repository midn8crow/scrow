# SCROW Changelog

All notable changes to the SCROW installer & dotfiles manager are documented here.
SCROW follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-08-12

### Added

- **New SCROW Installer & Manager** replacing the legacy `ORCHESTRA.sh` installer.
- Single entry point: `./install.sh` (or the one-line bootstrap).
- Professional keyboard-driven TUI manager with the main menu:
  Full Installation, Custom Installation, Components, Update, Restore,
  Reset, Doctor / Repair, Uninstall, Exit.
- Modular installer architecture under `installer/`:
  `core`, `ui`, `manifest`, `backup`, `packages`, `hardware`, `services`,
  `repository`, `components`, `commands`.
- **Component system** built from the real SCROW repository:
  Hyprland, Waybar, Rofi, Terminal, Mako, Shell, Theming, Utilities,
  Security Hardening, System Integration.
- **Automatic backup system** storing snapshots under
  `~/.local/share/scrow/backups/` before any potentially destructive operation.
- **Manifest system** tracking every SCROW-managed file, symlink, checksum,
  component and version under `~/.local/share/scrow/`.
- **Restore** — return to a previous automatic backup (restore is reversible).
- **Reset SCROW** — restore SCROW-managed files to the clean official
  repository state without touching anything SCROW does not own.
- **Update SCROW** — move to a newer SCROW version while preserving local
  modifications.
- **Doctor / Repair** — full health check with safe repairs.
- **Safe uninstall** with a final automatic backup.
- GPU / hardware detection (AMD, NVIDIA, Intel) with driver selection.
- `scrow` command installed to `~/.local/bin/scrow`.
- One-line bootstrap: `curl -fsSL https://raw.githubusercontent.com/midn8crow/scrow/main/bootstrap.sh | bash`
- `./install.sh --dry-run`, `--help`, `--version`.
- Detailed logs under `~/.local/share/scrow/logs/`.

### Changed

- Branding refreshed: SCROW • Arch Linux • Hyprland.
- `~/.zshrc` now adds `~/.local/bin` to `PATH` and uses SCROW branding.

### Removed (installer-level)

- The legacy `ORCHESTRA.sh` installer is no longer used by the new system.
  It remains in the repository for reference only.
