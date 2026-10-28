# Convy Auto Update Implementation Plan

> **For agentic workers:** Use executing-plans to implement this plan task-by-task. Execution remains in this session.

**Goal:** Check GitHub Releases automatically and offer Update & Restart.

**Architecture:** A Swift update controller validates GitHub metadata and downloaded app bundles. A bundled shell helper waits for exit, replaces the app in its writable installation directory, relaunches it, and restores the previous bundle on failure.

**Tech Stack:** Swift 6.2, Foundation URLSession, CryptoKit, AppKit, macOS shell utilities.

**Spec:** `docs/superpowers/specs/2026-10-28-auto-update-design.md`

## Global Constraints

- Apple Silicon, macOS 14+, no new framework, no sudo or Gatekeeper bypass.
- Check at launch and daily; manual checks in the menu; installation requires a click.
- Never interrupt a conversion or change original files or outputs.
- Keep the old app for rollback and refuse unwritable installations.

## Review Focus

- Version comparison must handle 0.4.10 after 0.4.9 and reject malformed releases.
- Metadata must reject foreign URLs, missing checksums, and wrong asset names.
- Download or validation failure must leave the installed app untouched.
- Replacement or relaunch failure must restore the old app.
- A conversion starting during download must prevent installation.

### Task 1: Release metadata and replacement helper

**Files:** `Source/UpdateRelease.swift`, `Source/UpdateTests.swift`, `Source/update-app.sh`, `Source/test-update.py`.

**Interfaces:** `UpdateRelease.parse(_:currentVersion:) throws -> UpdateRelease?`; helper takes old PID, installed bundle, staged bundle.

- [x] Write and run failing tests for valid/new/equal/old versions, invalid URLs/digests/tags, replacement success, and rollback.
- [x] Implement metadata validation and a helper that preserves the previous bundle and restores it if relaunch fails.
- [x] Run the Swift and helper tests.

### Task 2: App integration and packaging

**Files:** `Source/Updater.swift`, `Source/App.swift`, `Source/DragWheel.swift`, `Source/build.sh`, `Source/Info.plist`, `install.sh`, `Source/test-install.py`, `README.md`.

**Interfaces:** Observable main-actor updater exposes check/install state and checks conversion state again after download; drag wheel exposes processing state.

- [x] Add failing busy-state tests to the update tests.
- [x] Add launch/daily/manual checks, menu actions, download verification, bundle validation, conversion interlocks, and file-list confirmation.
- [x] Bundle the helper, build the app, and run conversion/update/installer tests.
- [x] Make the Terminal installer update safely using the same helper for the one-time upgrade.
- [ ] Publish the updater-enabled release and verify public metadata and download hashes.

## Verification limits

UI automation previously timed out. Attempt native verification again if available; otherwise report menu interaction and real app relaunch as unverified. Helper tests use an isolated filesystem and a controlled launcher so they never replace the user's installation.

## Execution notes

- Build, code signature, plist, Swift update tests with the actual app bundle, helper rollback/lock tests, installer tests, and conversion tests (`--skip-heic`) passed.
- Final independent review identified a concurrent-install race and missing replacement-failure coverage. Both have regression checks; locks now protect the destination.
- Native app inspection timed out again; real menu clicks and application relaunch remain unverified. Launch-command failure rollback is tested with an isolated launcher.
- Ruling: retain the previous app after successful launch acceptance, rather than deleting it; later crashes are outside automatic rollback and this is documented.
