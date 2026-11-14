#!/bin/sh
# Runs HotMessUITests/ReviewCodeE2ETests: signs in with an App Review code against a LOCAL fixture API and walks Now,
# an event (RSVP), a venue, People, Me and Sign Out, plus a wrong code.
#
#   HOTMESS_E2E_API_URL=http://127.0.0.1:3917 HOTMESS_E2E_REVIEW_CODE=… Scripts/review-e2e.sh
#   SIMULATOR="iPhone 18 Pro" or SIMULATOR_ID=<udid> picks the simulator ("iPhone 17 Pro" by default).
#   Extra arguments go to xcodebuild (e.g. -derivedDataPath …).
#
# The API: a clone of audience_kit_api in RAILS_ENV=test against a local throwaway database (hotmess_ui_test), with
# AUDIENCEKIT_UI_TEST=1 and AK_REVIEW_CODE set to a code you make up (16 letters and digits), after
# `bin/rails db:prepare ui_tests:setup`, served with UI_TEST_API_ORIGIN set to the same URL. Never point this at
# api.next.audiencekit.com or api.audiencekit.com (next shares the production database), and never use the real App
# Store review code. The code comes from the environment only.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${HOTMESS_E2E_API_URL:?Set HOTMESS_E2E_API_URL to the local fixture API, e.g. http://127.0.0.1:3917}"
: "${HOTMESS_E2E_REVIEW_CODE:?Set HOTMESS_E2E_REVIEW_CODE to the local API's AK_REVIEW_CODE}"
case "$HOTMESS_E2E_API_URL" in
  http://127.0.0.1:*|http://localhost:*|http://\[::1\]:*) ;;
  *) echo "HOTMESS_E2E_API_URL must be a local API, not $HOTMESS_E2E_API_URL" >&2; exit 1 ;;
esac
if [ -n "${SIMULATOR_ID:-}" ]; then
  DESTINATION="id=$SIMULATOR_ID"
else
  DESTINATION="platform=iOS Simulator,name=${SIMULATOR:-iPhone 17 Pro}"
fi

TEST_RUNNER_HOTMESS_E2E_API_URL="$HOTMESS_E2E_API_URL" \
TEST_RUNNER_HOTMESS_E2E_REVIEW_CODE="$HOTMESS_E2E_REVIEW_CODE" \
xcodebuild test \
  -project "$ROOT/HotMess.xcodeproj" \
  -scheme "HotMess Debug" \
  -destination "$DESTINATION" \
  -only-testing:HotMessUITests/ReviewCodeE2ETests \
  "$@"
