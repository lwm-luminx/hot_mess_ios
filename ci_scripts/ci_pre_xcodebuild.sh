#!/bin/sh
# Xcode Cloud runs this before each xcodebuild.
#
# Before an archive it decides whether the build is a beta: HOTMESS_BETA_SERVER = next in
# Configurations/Local.release.xcconfig, so a TestFlight install starts on the next API, shows the server
# switch in Me and wears the Next icon (AppConfiguration.isBetaInstall). App Review installs into the same
# sandbox as TestFlight, so a beta must never be submitted. A beta is opt-in: only an archive of `next` by a
# workflow that isn't a release workflow (the Next workflow, which archives for internal testing only) is one.
# Every other archive is an ordinary production build, and a release workflow (its name has "App Store" or
# "Release" in it, or is "Default") fails if any release xcconfig still sets the key. Both archive as the one
# app, social.hotmess.HotMess.
#
# Before build-for-testing it points the UI tests at the server for the branch being built (the
# .xctestrun carries it to test-without-building, which runs without the repository): main talks to
# production, every other branch (next, feature branches) to the next API. A pull request build uses the
# branch it targets. The tests read it as HOTMESS_TEST_API_URL (see XCUIApplication.runnerAPI). The
# sign-in tests still skip here: they need real accounts.
set -eu

branch="${CI_BRANCH:-${CI_PULL_REQUEST_TARGET_BRANCH:-}}"

if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
    workflow="${CI_WORKFLOW:-}"
    case "$workflow" in
    *"App Store"* | *Release* | Default) release=yes ;;
    *) release=no ;;
    esac
    if [ "$release" = no ] && [ "$branch" = next ]; then
        printf 'HOTMESS_BETA_SERVER = next\n' >>"$CI_PRIMARY_REPOSITORY_PATH/Configurations/Local.release.xcconfig"
        echo "Archiving '$branch' ('$workflow') as a beta: TestFlight installs start on the next API"
        exit 0
    fi
    if grep -Eqs '^[[:space:]]*HOTMESS_BETA_SERVER[[:space:]]*=[[:space:]]*[^[:space:]/]' \
        "$CI_PRIMARY_REPOSITORY_PATH"/Configurations/*.xcconfig; then
        echo "error: HOTMESS_BETA_SERVER is set in Configurations, so '$branch' ('$workflow') would archive as a beta." >&2
        echo "error: App Review would see it on the next API. Remove the setting; only the Next workflow on next sets it." >&2
        exit 1
    fi
    echo "Archiving '$branch' ('$workflow') as a production build, not a beta"
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
