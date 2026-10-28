#!/bin/bash
set -euo pipefail

expected_sha256="5aa7467358ad30fb2324bd82e4295459b8a00010fba4b948392eb0284c0f4b06"
if [[ -z "$expected_sha256" ]]; then
    echo "Convio release is not configured yet. Build a new archive and set its SHA-256 before publishing." >&2
    exit 1
fi

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo 'Convio requires an Apple Silicon Mac.' >&2
    exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 14 )); then
    echo 'Convio requires macOS 14 or later.' >&2
    exit 1
fi

destination="$HOME/Applications/Convio.app"
if [[ -L "$destination" || ( -e "$destination" && ! -d "$destination" ) ]]; then
    echo "The installation path is not an app directory: $destination" >&2
    exit 1
fi
if pgrep -x Convio >/dev/null; then
    echo 'Quit Convio from its menu bar, then run this command again.' >&2
    exit 1
fi

mkdir -p "$HOME/Applications"
work=$(mktemp -d "$HOME/Applications/.Convio-update.XXXXXX")
lock=''
trap 'if [[ -n "$lock" ]]; then rmdir "$lock" 2>/dev/null || true; fi; if [[ ! -e "$work/Previous.app" ]]; then rm -rf "$work"; fi' EXIT
curl --fail --location --show-error --silent \
    https://github.com/byhaqii/Convio/releases/download/v0.4.7/Convio-0.4.7-arm64.zip \
    -o "$work/Convio.zip"
echo "$expected_sha256  $work/Convio.zip" | shasum -a 256 -c -
ditto -x -k "$work/Convio.zip" "$work"
codesign --verify --deep --strict "$work/Convio.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$work/Convio.app/Contents/Info.plist")" == com.shustle.convio ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/Convio.app/Contents/Info.plist")" == 0.4.7 ]]
lipo "$work/Convio.app/Contents/MacOS/Convio" -verify_arch arm64
if [[ -d "$destination" ]]; then
    if pgrep -x Convio >/dev/null; then
        echo 'Quit Convio before updating. Nothing was replaced.' >&2
        exit 1
    fi
    cp "$work/Convio.app/Contents/Resources/update-app.sh" "$work/update-app.sh"
    bash "$work/update-app.sh" 0 "$destination" "$work/Convio.app"
else
    lock="$destination.update-lock"
    mkdir "$lock" || { lock=''; echo 'Another Convio installation is already in progress.' >&2; exit 1; }
    if [[ -e "$destination" || -L "$destination" ]]; then
        echo 'Another installation completed. Run the command again to update it.' >&2
        exit 1
    fi
    mv "$work/Convio.app" "$destination"
fi
echo "Installed: $destination"
echo 'Open Convio from your Applications folder in your home directory.'
echo 'If macOS blocks it, use System Settings > Privacy & Security > Open Anyway.'
