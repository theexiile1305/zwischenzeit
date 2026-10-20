#!/bin/bash
# Selects the newest Xcode installed on a GitHub macOS runner and prints its version.
set -euo pipefail
XCODE=$(find /Applications -maxdepth 1 -name 'Xcode_*.app' -not -name '*beta*' | sort -V | tail -1)
if [[ -z $XCODE ]]; then
  XCODE=/Applications/Xcode.app
fi
sudo xcode-select --switch "$XCODE/Contents/Developer"
xcodebuild -version
swift --version
