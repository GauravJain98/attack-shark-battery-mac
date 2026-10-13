#!/bin/sh
set -eu
cd "$(dirname "$0")"

app=build/AttackSharkBattery.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Info.plist "$app/Contents/Info.plist"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
xcrun swiftc -O main.swift -o "$app/Contents/MacOS/AttackSharkBattery"
codesign --force --sign - "$app"
echo "Built $app"
