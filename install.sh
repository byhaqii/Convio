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
if [[ -e "$destination" || -L "$destination" ]]; then
    echo "Convy already exists at $destination. Move it aside before reinstalling." >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl --fail --location --show-error --silent \
    https://github.com/byhaqii/Convy/releases/download/v0.4.1/Convy-0.4.1-arm64.zip \
    -o "$work/Convy.zip"
echo "3c513ec60d2c3f68a4487360087bee4dd07f5244022da1eeb6c5649cc2f789c8  $work/Convy.zip" | shasum -a 256 -c -
ditto -x -k "$work/Convy.zip" "$work"
codesign --verify --deep --strict "$work/Convy.app"
mkdir -p "$HOME/Applications"
mv "$work/Convy.app" "$destination"
echo "Installed: $destination"
echo 'Open Convy from your Applications folder in your home directory.'
echo 'If macOS blocks it, use System Settings > Privacy & Security > Open Anyway.'
