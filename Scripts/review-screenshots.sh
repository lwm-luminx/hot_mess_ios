#!/usr/bin/env bash
# Runs ReviewCodeScreenshots (the App Store review screens, signed in with App Review codes) and saves the PNGs.
#
#   Scripts/review-screenshots.sh                  production: the installed Release build (social.hotmess.HotMess)
#   Scripts/review-screenshots.sh next             the Screenshots scheme's build, on the next API
#
# Reads APP_REVIEW_CODE and APP_REVIEW_BANNED_CODE (and any HOTMESS_UITEST_* overrides) from the audience-kit root .env,
# or ENV_FILE, and hands them to the test runner without printing them. Set DEVICE to pick the simulator (default
# "iPhone 17 Pro Max"), TEST to run one test (testReviewerScreens or testBannedReviewerScreens), and OUT for where the PNGs go (default ~/Desktop/hotmess-app-review-screens/ui-test).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-production}"
env_file="${ENV_FILE:-$repo/../../../.env}"
device="${DEVICE:-iPhone 17 Pro Max}"
out="${OUT:-$HOME/Desktop/hotmess-app-review-screens/ui-test}"

# Exported rather than passed as arguments: xcodebuild forwards TEST_RUNNER_* variables to the runner, and prints
# command-line build settings in its log.
if [[ -f "$env_file" ]]; then
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^(APP_REVIEW_CODE|APP_REVIEW_BANNED_CODE|HOTMESS_UITEST_[A-Z_]+)$ ]] || continue
    value="${value%\"}"; value="${value#\"}"
    export "TEST_RUNNER_$key=$value"
  done < "$env_file"
else
  echo "No .env at $env_file; using TEST_RUNNER_* from the environment only." >&2
fi
export TEST_RUNNER_HOTMESS_UITEST_SCREENSHOT_DIR="$out"
[[ "$target" == production ]] && export TEST_RUNNER_HOTMESS_UITEST_BUNDLE_ID=social.hotmess.HotMess

# By UDID: a name alone can match nothing when several runtimes are installed.
udid="$(xcrun simctl list devices available | grep -F "    $device (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[[ -n "$udid" ]] || { echo "No available simulator named $device" >&2; exit 1; }

mkdir -p "$out"
cd "$repo"
xcodebuild test -project HotMess.xcodeproj -scheme "HotMess Screenshots" \
  -destination "platform=iOS Simulator,id=$udid" \
  -only-testing:"HotMessScreenshots/ReviewCodeScreenshots${TEST:+/$TEST}"
echo "Screenshots in $out"
