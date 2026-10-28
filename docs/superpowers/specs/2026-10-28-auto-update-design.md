# Convy app updates

Convy checks GitHub Releases when it starts and once per day while running. A menu bar item also lets users check manually. A newer compatible release offers **Update & Restart**; installation never starts without that choice.

## Approaches

- Terminal installer upgrades: smallest change, but still requires users to run a command.
- In-app checks and installation: selected by baws; users update from Convy's menu bar.

## Behavior and constraints

- Keep the existing Swift app and GitHub Releases distribution. Use macOS networking and a small local installation helper; no new framework.
- Download only the expected Apple Silicon release asset from the Convy repository. Validate release metadata, SHA-256, app identity, version, architecture, and code signature before replacement. Ad-hoc signing does not establish publisher identity; HTTPS and the repository remain the distribution trust boundary.
- Disable installation during any conversion, including the drag wheel. Network errors leave Convy usable and are shown for manual checks; automatic checks fail quietly.
- Stage the app beside the current installation, retain the previous app until replacement and relaunch succeed, and restore it on installation failure. Support writable app locations without sudo; report permission errors without changing the installation.
- Explain that restarting clears the current file list and ask before continuing when files are loaded. Original files and conversion outputs are untouched.
- Keep macOS Gatekeeper protections enabled. Notarization and signing with a Developer ID are outside this change.
- Update the release packaging, installer, documentation, and checks together. Test metadata/version handling, corrupted downloads, busy-state protection, replacement, and rollback.

## First upgrade

Existing v0.4.2 installations cannot update themselves. Users must install the updater-enabled release once with Terminal. Subsequent releases can update through Convy.

## Scope

No silent installation, launch at login, Windows/Linux support, or release-management UI. Visual behavior and actual relaunch must be verified where UI automation is available; limitations must be reported otherwise.
