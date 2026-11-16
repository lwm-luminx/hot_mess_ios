#!/bin/sh
# Runs the HotMessTests unit bundle (never the UI or screenshot tests) with code
# coverage on an iOS simulator, then prints the app's line coverage per file.
#
#   Scripts/unit-tests.sh                       # "iPhone 17 Pro" simulator
#   SIMULATOR="iPhone 18 Pro" Scripts/unit-tests.sh
#   SIMULATOR_ID=<udid> Scripts/unit-tests.sh   # a particular simulator
#   Scripts/unit-tests.sh Screens               # only files whose path matches
#
# Everything runs offline: the screen tests answer every request from a stub
# (HotMessTests/Support/ScreenTestSupport.swift) and fail on any other.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FILTER=${1:-}
OUT=${OUT:-$(mktemp -d)}
RESULT="$OUT/HotMessTests.xcresult"
if [ -n "${SIMULATOR_ID:-}" ]; then
  DESTINATION="id=$SIMULATOR_ID"
else
  DESTINATION="platform=iOS Simulator,name=${SIMULATOR:-iPhone 17 Pro}"
fi

rm -rf "$RESULT"
xcodebuild test \
  -project "$ROOT/HotMess.xcodeproj" \
  -scheme "HotMess Debug" \
  -destination "$DESTINATION" \
  -only-testing:HotMessTests \
  -enableCodeCoverage YES \
  -resultBundlePath "$RESULT" \
  -quiet

echo
xcrun xccov view --report --only-targets "$RESULT" | grep -E "Coverage|HotMess.app"
echo
xcrun xccov view --report --files-for-target HotMess.app "$RESULT" \
  | awk -v root="$ROOT/" -v filter="$FILTER" '
      $2 ~ /\.swift$/ && (filter == "" || index($2, filter) > 0) {
        path = $2; sub(root, "", path)
        printf "%-8s %-14s %s\n", $(NF-1), $NF, path
      }' \
  | sort -k3
echo
echo "Result bundle: $RESULT"
