#!/bin/bash
# Archives the iOS app (with the embedded watch app) and uploads it to TestFlight.
#   scripts/testflight.sh
# Needs Config/Local.xcconfig with your BUNDLE_ID_PREFIX and DEVELOPMENT_TEAM, an Xcode account
# signed in to that team (Xcode → Settings → Accounts), and the app record in App Store Connect.
# The build number is a UTC timestamp, so every upload is higher than the last without a commit.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=$(xcodebuild -project Zwischenzeit.xcodeproj -scheme Zwischenzeit -showBuildSettings \
  -destination 'generic/platform=iOS' 2>/dev/null | sed -nE 's/^ *DEVELOPMENT_TEAM = (.+)$/\1/p' | head -1)
if [[ -z $TEAM ]]; then
  echo "DEVELOPMENT_TEAM is empty. Copy Config/Local.xcconfig.example to Config/Local.xcconfig first." >&2
  exit 1
fi

BUILD=$(date -u +%Y%m%d%H%M)
ARCHIVE=build/Zwischenzeit-$BUILD.xcarchive
echo "Archiving build $BUILD for team $TEAM"
xcodebuild archive -project Zwischenzeit.xcodeproj -scheme Zwischenzeit -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates -quiet

echo "Uploading to App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "build/export-$BUILD" -allowProvisioningUpdates

echo "Uploaded build $BUILD. It appears in TestFlight after processing (usually 5-15 minutes)."
