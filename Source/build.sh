#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../Convio.app/Contents/MacOS ../Convio.app/Contents/Resources
swiftc -module-cache-path "${TMPDIR:-/tmp}/convio-module-cache" -target arm64-apple-macos14.0 -swift-version 6 -parse-as-library -O Converter.swift DragWheel.swift InstanceLock.swift UpdateRelease.swift UpdateValidation.swift Updater.swift App.swift -o ../Convio.app/Contents/MacOS/Convio
cp Info.plist ../Convio.app/Contents/Info.plist
cp Assets/AppIcon.icns ../Convio.app/Contents/Resources/AppIcon.icns
cp update-app.sh ../Convio.app/Contents/Resources/update-app.sh
codesign --force --sign - ../Convio.app
echo 'Built Convio.app'
