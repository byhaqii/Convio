#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo 'Convy requires an Apple Silicon Mac.' >&2
    exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 14 )); then
    echo 'Convy requires macOS 14 or later.' >&2
    exit 1
fi

destination="$HOME/Applications/Convy.app"
if [[ -L "$destination" || ( -e "$destination" && ! -d "$destination" ) ]]; then
    echo "The installation path is not an app directory: $destination" >&2
    exit 1
fi
if pgrep -x Convy >/dev/null; then
    echo 'Quit Convy from its menu bar, then run this command again.' >&2
    exit 1
fi

mkdir -p "$HOME/Applications"
work=$(mktemp -d "$HOME/Applications/.Convy-update.XXXXXX")
lock=''
trap 'if [[ -n "$lock" ]]; then rmdir "$lock" 2>/dev/null || true; fi; if [[ ! -e "$work/Previous.app" ]]; then rm -rf "$work"; fi' EXIT
curl --fail --location --show-error --silent \
    https://github.com/byhaqii/Convy/releases/download/v0.4.6/Convy-0.4.6-arm64.zip \
    -o "$work/Convy.zip"
echo "1b356249d2cb6ec3efc6a150311366abd4dc7ad0d2a50490c664494123682e6c  $work/Convy.zip" | shasum -a 256 -c -
ditto -x -k "$work/Convy.zip" "$work"
codesign --verify --deep --strict "$work/Convy.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$work/Convy.app/Contents/Info.plist")" == com.shustle.convy ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/Convy.app/Contents/Info.plist")" == 0.4.6 ]]
lipo "$work/Convy.app/Contents/MacOS/Convy" -verify_arch arm64
if [[ -d "$destination" ]]; then
    if pgrep -x Convy >/dev/null; then
        echo 'Quit Convy before updating. Nothing was replaced.' >&2
        exit 1
    fi
    cp "$work/Convy.app/Contents/Resources/update-app.sh" "$work/update-app.sh"
    bash "$work/update-app.sh" 0 "$destination" "$work/Convy.app"
else
    lock="$destination.update-lock"
    mkdir "$lock" || { lock=''; echo 'Another Convy installation is already in progress.' >&2; exit 1; }
    if [[ -e "$destination" || -L "$destination" ]]; then
        echo 'Another installation completed. Run the command again to update it.' >&2
        exit 1
    fi
    mv "$work/Convy.app" "$destination"
fi
echo "Installed: $destination"
echo 'Open Convy from your Applications folder in your home directory.'
echo 'If macOS blocks it, use System Settings > Privacy & Security > Open Anyway.'
