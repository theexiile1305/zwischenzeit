#!/bin/bash
# Build, install and screenshot the iOS app in the simulator with a frozen clock.
#   scripts/screenshot.sh <output.png> [extra launch args...]
# Example: scripts/screenshot.sh month.png -calendarMode month
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
OUT=${1:?usage: scripts/screenshot.sh <output.png> [launch args...]}; shift
DEVICE=${DEVICE:-"iPhone 18 Pro"}
APPEARANCE=${APPEARANCE:-light}
cd "$(dirname "$0")/.."
UDID=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [[ -z $UDID ]]; then
  echo "No available simulator named '$DEVICE'. Set DEVICE to one from 'xcrun simctl list devices'." >&2
  exit 1
fi
if [[ -z ${SKIP_BUILD:-} ]]; then
  xcodebuild build -project Zwischenzeit.xcodeproj -scheme Zwischenzeit \
    -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build/dd -quiet
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance "$APPEARANCE"
xcrun simctl status_bar "$UDID" override --time 09:28 --batteryState charged --batteryLevel 100 --cellularBars 4
APP=build/dd/Build/Products/Debug-iphonesimulator/Zwischenzeit.app
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -fixedNow "${NOW:-2026-10-14T09:28:00+02:00}" "$@" >/dev/null
sleep "${WAIT:-4}"
xcrun simctl io "$UDID" screenshot "$OUT" >/dev/null 2>&1
echo "$OUT"
