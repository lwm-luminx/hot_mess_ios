#!/bin/sh
# Xcode Cloud runs this after each xcodebuild. After a successful archive (the build Xcode Cloud then uploads to
# TestFlight) it tells the AudienceKit API about the new build, so testers on older builds are offered it: the
# release config's TestFlight `latest_build` (the update prompts, #386; doc/design-system/TestFlightUpdates.md in
# audience-kit).
#
#   1. POST {api}/v1/token/service { "service_token": $AUDIENCEKIT_RELEASE_TOKEN } -> { "token": "<service JWT>" }
#   2. PUT  {api}/v1/app_release   { "app", "channel": "testflight", "latest_build", "latest_version", "available_at" }
#
# `available_at` is half an hour out, roughly when TestFlight has processed the build. Only beta archives report
# (next and feature branches, to the next API): main and next are one app now, and both APIs share a database, so a
# main build reporting too would offer TestFlight testers a build their group doesn't get. Set
# AUDIENCEKIT_RELEASE_TOKEN (a service token, `akst_…`) as a secret environment variable in the workflow; without it
# this logs a line and does nothing. A reporting failure never fails the build.
set -u

log() { echo "ci_post_xcodebuild: $*"; }

[ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] || exit 0
if [ "${CI_XCODEBUILD_EXIT_CODE:-0}" != "0" ]; then
    log "the archive failed; not reporting the build"
    exit 0
fi
if [ -z "${AUDIENCEKIT_RELEASE_TOKEN:-}" ]; then
    log "AUDIENCEKIT_RELEASE_TOKEN isn't set; not reporting the build to AudienceKit"
    exit 0
fi

branch="${CI_BRANCH:-${CI_PULL_REQUEST_TARGET_BRANCH:-}}"
if [ "$branch" = "main" ]; then
    log "main archives are App Store candidates; not reporting the build to TestFlight's channel"
    exit 0
fi
api="https://api.next.audiencekit.com"
api="${AUDIENCEKIT_API_URL:-$api}" # an override, for trying the script against a local API

# The archived app's own Info.plist values, falling back to what Xcode Cloud says.
plist_value() {
    [ -n "${CI_ARCHIVE_PATH:-}" ] && [ -f "$CI_ARCHIVE_PATH/Info.plist" ] || return 0
    /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:$1" "$CI_ARCHIVE_PATH/Info.plist" 2>/dev/null || true
}
app="$(plist_value CFBundleIdentifier)"
[ -n "$app" ] || app="${CI_BUNDLE_ID:-}"
version="$(plist_value CFBundleShortVersionString)"
if [ -z "$version" ] && [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
    version="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' \
        "$CI_PRIMARY_REPOSITORY_PATH/HotMess.xcodeproj/project.pbxproj" 2>/dev/null | head -n 1)"
fi
build="${CI_BUILD_NUMBER:-}"

case "$build" in
'' | *[!0-9]*)
    log "CI_BUILD_NUMBER '$build' isn't a build number; not reporting the build"
    exit 0
    ;;
esac
if [ -z "$app" ]; then
    log "couldn't tell the archive's bundle ID; not reporting the build"
    exit 0
fi

available_at="$(date -u -v+30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

# Reads a top-level string from JSON on stdin.
json_string() {
    if command -v plutil >/dev/null 2>&1; then
        plutil -extract "$1" raw -o - - 2>/dev/null
    else
        python3 -c 'import json,sys; v=json.load(sys.stdin).get(sys.argv[1]); print(v if isinstance(v, str) else "")' "$1" 2>/dev/null
    fi
}

# Escapes a value for a JSON string.
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

headers_file="$(mktemp)"
trap 'rm -f "$headers_file"' EXIT

# 1. The service token for a short-lived service JWT. The secret goes in the body, never on the command line's URL.
exchange="$(printf '{"service_token":"%s"}' "$(json_escape "$AUDIENCEKIT_RELEASE_TOKEN")" |
    curl -sS --max-time 30 -X POST "$api/v1/token/service" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' --data-binary @- \
        -w '\n%{http_code}' 2>&1)"
status="$(printf '%s' "$exchange" | tail -n 1)"
if [ "$status" != "200" ]; then
    log "couldn't exchange the service token at $api (HTTP $status); not reporting build $build"
    exit 0
fi
jwt="$(printf '%s' "$exchange" | sed '$d' | json_string token)"
if [ -z "$jwt" ]; then
    log "the token exchange at $api returned no token; not reporting build $build"
    exit 0
fi

# 2. The build, as the TestFlight channel's latest.
latest_version=null
[ -z "$version" ] || latest_version="\"$(json_escape "$version")\""
body="$(printf '{"app":"%s","channel":"testflight","latest_build":%s,"latest_version":%s,"available_at":"%s"}' \
    "$(json_escape "$app")" "$build" "$latest_version" "$available_at")"
printf 'Authorization: Bearer %s\n' "$jwt" >"$headers_file"
result="$(printf '%s' "$body" |
    curl -sS --max-time 30 -X PUT "$api/v1/app_release" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' -H "@$headers_file" --data-binary @- \
        -o /dev/null -w '%{http_code}' 2>&1)"
case "$result" in
2??) log "reported $app $version ($build) to $api as TestFlight's latest build, available at $available_at" ;;
*) log "couldn't report $app $version ($build) to $api (HTTP $result)" ;;
esac
exit 0
