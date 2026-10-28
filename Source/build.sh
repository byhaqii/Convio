#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../Convy.app/Contents/MacOS ../Convy.app/Contents/Resources
swiftc -module-cache-path "${TMPDIR:-/tmp}/convy-module-cache" -target arm64-apple-macos14.0 -swift-version 6 -parse-as-library -O Converter.swift DragWheel.swift App.swift -o ../Convy.app/Contents/MacOS/Convy
cp Info.plist ../Convy.app/Contents/Info.plist
cp Assets/AppIcon.icns ../Convy.app/Contents/Resources/AppIcon.icns
codesign --force --sign - ../Convy.app
echo 'Built Convy.app'
