#!/bin/sh
set -eu
cd "$(dirname "$0")"

./build.sh

destination="$HOME/Applications/AttackSharkBattery.app"
pkill -x AttackSharkBattery 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$destination"
cp -R build/AttackSharkBattery.app "$destination"
open "$destination"
echo "Installed to $destination"
