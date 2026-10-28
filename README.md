# Convy

A local image and PDF converter for Apple Silicon Macs running macOS 14 or later.

Version 0.4.1 includes the rounded jade-glass C app icon. The raster master and macOS icon are in `Source/Assets/`; the build script installs the icon automatically.

## Use

### Install from Terminal

On an Apple Silicon Mac running macOS 14 or later, paste:

```sh
curl -fsSL https://github.com/byhaqii/Convy/releases/latest/download/install.sh | /bin/bash
```

This downloads the compiled app, checks its SHA-256 and signature, and installs it in `~/Applications`. No Xcode or sudo is needed. Open Convy from that folder. The installer refuses to overwrite an existing installation; move it aside to reinstall.

The app is ad-hoc signed and not notarized. If macOS blocks it, approve it in **System Settings → Privacy & Security → Open Anyway**.

Open **Convy.app**. Convy runs in the background with a circular-arrows icon in the macOS menu bar and no Dock icon. Click the icon for **Open Convy**, **Open Wheel**, or **Quit Convy**. Closing the converter window keeps Convy running; opening it again preserves the current file list. Convy does not automatically start at login.

Hold **Shift** while dragging a file in Finder, then drop it onto JPG, PNG, HEIC, or PDF. The rounded glass wheel appears near the pointer. Results are saved beside the source with a new name; originals and existing files are never overwritten.

You can also choose files, output format, quality, and destination in the main window. **Buka roda** opens the wheel manually. Escape closes it.

- PDF-to-image exports every page separately at 144 DPI, with numbered filenames.
- Image-to-PDF creates one PDF per image.
- The wheel uses 85% quality for JPG/HEIC. It appears over 180 ms and shrinks away over 120 ms immediately after conversion. Reduce Motion uses an 80 ms fade.
- macOS 26 uses native Liquid Glass. Earlier supported macOS versions use frosted material.
- No accounts, uploads, analytics, network requests, or Homebrew dependencies.

## Limits

Animated images, locked PDFs, and PDF-to-PDF conversion are rejected. Images/pages are limited to 80 megapixels and 20,000 pixels per side. Metadata is not copied; orientation is applied to pixels. JPG uses a white background for transparency. Color/HDR and quality can change during conversion.

The app is locally ad-hoc signed, not Apple-notarized. Intel Macs and older macOS releases have not been tested.

Quit the old Berkas app before opening Convy so that only one Shift-drag wheel runs.

## Build

Requires the Swift 6.2 toolchain and macOS 26 SDK, supplied by Xcode 26.

```sh
bash Source/build.sh
```

## Test

```sh
swiftc -swift-version 6 -parse-as-library Source/Converter.swift Source/DragWheel.swift Source/Tests.swift -o /tmp/convy-tests
/tmp/convy-tests
```

Use `--skip-heic` when running tests in environments that block the hardware encoder. HEIC was tested through the previous app build on this Mac.

Version 0.4 verification: build and local signature passed; conversion, multi-page PDF, original-file protection, duplicate names, EXIF orientation, invalid input, and rounded-sector hit tests passed. The Convy name, rounded wheel, and Escape dismissal were checked in the running app. Other Macs and frame-by-frame animation timing were not checked.

## GitHub

Source is hosted at [byhaqii/Convy](https://github.com/byhaqii/Convy). Compiled downloads and the installer are available in [Releases](https://github.com/byhaqii/Convy/releases). Build outputs are ignored.
