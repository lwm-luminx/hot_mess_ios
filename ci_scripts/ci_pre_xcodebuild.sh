#!/bin/sh
# Xcode Cloud runs this before each xcodebuild.
#
# Before an archive of any branch but main it makes the build a beta: HOTMESS_BETA_SERVER = next in
# Configurations/Local.release.xcconfig, so a TestFlight install starts on the next API, shows the server
# switch in Me and wears the Next icon (AppConfiguration.isBetaInstall). The App Store never gets these
# builds, and main archives (App Store candidates, which App Review installs into the same sandbox as
# TestFlight) stay ordinary. Both archive as the one app, social.hotmess.HotMess.
#
# Before build-for-testing it points the UI tests at the server for the branch being built (the
# .xctestrun carries it to test-without-building, which runs without the repository): main talks to
# production, every other branch (next, feature branches) to the next API. A pull request build uses the
# branch it targets. The tests read it as HOTMESS_TEST_API_URL (see XCUIApplication.runnerAPI). The
# sign-in tests still skip here: they need real accounts.
set -eu

branch="${CI_BRANCH:-${CI_PULL_REQUEST_TARGET_BRANCH:-}}"

if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
    if [ "$branch" != "main" ]; then
        printf 'HOTMESS_BETA_SERVER = next\n' >>"$CI_PRIMARY_REPOSITORY_PATH/Configurations/Local.release.xcconfig"
        echo "Archiving '$branch' as a beta: TestFlight installs start on the next API"
    fi
    exit 0
fi

[ "${CI_XCODEBUILD_ACTION:-}" = "build-for-testing" ] || exit 0

case "$branch" in
main) api="https://api.audiencekit.com" ;;
*) api="https://api.next.audiencekit.com" ;;
esac

scheme="$CI_PRIMARY_REPOSITORY_PATH/HotMess.xcodeproj/xcshareddata/xcschemes/$CI_XCODE_SCHEME.xcscheme"
if ! grep -q "HOTMESS_TEST_API_URL" "$scheme"; then
    HOTMESS_TEST_API_URL="$api" perl -0pi -e '
        s{(<TestAction\b[^>]*?)shouldUseLaunchSchemeArgsEnv = "YES">}{$1shouldUseLaunchSchemeArgsEnv = "NO">
      <EnvironmentVariables>
         <EnvironmentVariable
            key = "HOTMESS_TEST_API_URL"
            value = "$ENV{HOTMESS_TEST_API_URL}"
            isEnabled = "YES">
         </EnvironmentVariable>
      </EnvironmentVariables>}
    ' "$scheme"
fi
grep -q "value = \"$api\"" "$scheme" || { echo "error: couldn't set HOTMESS_TEST_API_URL in $scheme" >&2; exit 1; }
echo "UI tests on branch '$branch' use $api"
