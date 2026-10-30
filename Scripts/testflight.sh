#!/usr/bin/env bash
# Archives the selected build (Release by default), exports it for App Store Connect and uploads it to TestFlight.
#
#   Scripts/testflight.sh                 # archive, export and upload
#   Scripts/testflight.sh --next          # a beta: TestFlight installs start on the next API
#   Scripts/testflight.sh --export-only   # stop after exporting build/testflight/export/HotMess.ipa
#
# The build number defaults to the minutes since 2026-01-01 UTC, so every upload is newer than
# the last; set BUILD_NUMBER to choose one. Signing is automatic with team DWVXMLB45Y, so Xcode needs
# to be signed in to an account on that team, with an Apple Distribution certificate in the keychain.
#
# The upload uses an App Store Connect API key (Users and Access -> Integrations -> Team Keys,
# role App Manager or Developer), found in the login keychain the way garage-rag finds it:
# garage-rag's item (service me.rickmark.garage-rag.asc-api-key), else the one the `asc` CLI
# saves for this Mac (account asc:credential:<LocalHostName>), else one labelled
# "ASC API Key (<LocalHostName>)". ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file)
# override it.
set -euo pipefail

KEYCHAIN_SERVICE="me.rickmark.garage-rag.asc-api-key"
TEAM_ID="DWVXMLB45Y"

die() {
    echo "testflight: $*" >&2
    exit 1
}

mode="upload"
configuration="Release"
scheme="HotMess Release"
channel="production"
beta_server=""
for argument in "$@"; do
    case "$argument" in
        --export-only) mode="export" ;;
        --next) channel="next"; beta_server="next" ;;
        *) die "unknown argument $argument" ;;
    esac
done

root="$(cd "$(dirname "$0")/.." && pwd -P)"
out="$root/build/testflight"
[[ "$channel" == "next" ]] && out="$root/build/testflight-next"
# Minutes since 2026-01-01 UTC: always increasing, and small enough for the API's 32-bit
# sessions.build column. (A yyyymmddHHMM stamp overflowed it and failed every sign-in.)
build_number="${BUILD_NUMBER:-$(( ($(date -u +%s) - 1767225600) / 60 ))}"

work="$(mktemp -d "${TMPDIR:-/tmp}/hotmess-testflight.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Credentials come before the slow archive, so a missing key fails at once.
if [[ "$mode" == "upload" ]]; then
    mkdir -m 700 "$work/private_keys"
    key_id="${ASC_KEY_ID:-}" issuer_id="${ASC_ISSUER_ID:-}"
    if [[ -n "${ASC_KEY_PATH:-}" ]]; then
        [[ -n "$key_id" && -n "$issuer_id" ]] || die "ASC_KEY_PATH needs ASC_KEY_ID and ASC_ISSUER_ID"
        cp "$ASC_KEY_PATH" "$work/private_keys/AuthKey_$key_id.p8"
    else
        # garage-rag's own item, else the one the `asc` App Store Connect CLI saves for this Mac
        # (account asc:credential:<LocalHostName>), else one labelled "ASC API Key (<name>)".
        host="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
        item=() attributes=""
        for candidate in "-s|$KEYCHAIN_SERVICE" "-a|asc:credential:$host" "-l|ASC API Key ($host)"; do
            if attributes="$(security find-generic-password "${candidate%%|*}" "${candidate#*|}" 2>/dev/null)"; then
                item=("${candidate%%|*}" "${candidate#*|}")
                break
            fi
        done
        [[ ${#item[@]} -gt 0 ]] ||
            die "no App Store Connect API key in the keychain; store it once with:
  security add-generic-password -U -s $KEYCHAIN_SERVICE -a <KEY ID> -j <ISSUER ID> -w \"\$(base64 < AuthKey_<KEY ID>.p8)\""
        secret="$(security find-generic-password "${item[@]}" -w)" || die "could not read the API key from the keychain"
        # The password may be the .p8 itself, its base64, the hex `security` prints for multi-line data,
        # or JSON with the key and its IDs. The IDs come from the environment, that JSON or an
        # asc:metadata: attribute, then the item's account (key ID) and comment (issuer ID).
        ids="$(umask 077 && KEY_ID="$key_id" ISSUER_ID="$issuer_id" SECRET="$secret" ATTRIBUTES="$attributes" \
            /usr/bin/python3 - "$work/private_keys" <<'PY'
import base64, binascii, json, os, re, sys

secret = os.environ["SECRET"].strip()
fields = {}

def pem(text):
    return text if "PRIVATE KEY-----" in text else None

def normalise(items):
    return {k.lower().replace("_", "").replace("-", ""): v for k, v in items if isinstance(v, str)}

if re.fullmatch(r"[0-9a-fA-F]+", secret) and len(secret) % 2 == 0:
    secret = binascii.unhexlify(secret).decode("utf-8", "replace").strip()
key = None
if secret.startswith("{"):
    fields = normalise(json.loads(secret).items())
    key = next((pem(v) for v in fields.values() if pem(v)), None)
    if key is None:
        path = next((v for v in fields.values() if v.endswith(".p8") and os.path.isfile(os.path.expanduser(v))), None)
        key = pem(open(os.path.expanduser(path)).read()) if path else None
else:
    key = pem(secret)
if key is None:
    try:
        key = pem(base64.b64decode(secret, validate=True).decode("utf-8"))
    except (binascii.Error, UnicodeDecodeError):
        pass
if key is None:
    sys.exit("the keychain item holds no recognizable .p8 private key")

attrs = dict(re.findall(r'^\s*"(\w+)"<blob>="(.*)"$', os.environ["ATTRIBUTES"], re.M))
for value in attrs.values():
    if value.startswith("asc:metadata:"):
        fields.update(normalise(json.loads(value.removeprefix("asc:metadata:")).items()))
uuid = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
key_id = os.environ["KEY_ID"] or fields.get("keyid") or fields.get("apikey") or ""
if not key_id and re.fullmatch(r"[A-Z0-9]{4,}", attrs.get("acct", "")):
    key_id = attrs["acct"]
issuer = os.environ["ISSUER_ID"] or fields.get("issuerid") or fields.get("issuer") or attrs.get("icmt", "")
if not issuer:
    issuer = next((m.group(0) for v in attrs.values() if (m := re.search(uuid, v))), "")
if not key_id or not issuer:
    sys.exit("found the key but not its key ID or issuer ID; set ASC_KEY_ID and ASC_ISSUER_ID")
with open(os.path.join(sys.argv[1], f"AuthKey_{key_id}.p8"), "w") as f:
    f.write(key.strip() + "\n")
print(key_id, issuer)
PY
        )" || die "could not use the API key in the keychain item ${item[*]}"
        read -r key_id issuer_id <<<"$ids"
    fi
fi

rm -rf "$out"
mkdir -p "$out"

echo "==> Archiving $scheme, build $build_number"
xcodebuild archive \
    -project "$root/HotMess.xcodeproj" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    -destination "generic/platform=iOS" \
    -archivePath "$out/HotMess.xcarchive" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CURRENT_PROJECT_VERSION="$build_number" \
    HOTMESS_BETA_SERVER="$beta_server" \
    APNS_ENVIRONMENT=production

echo "==> Exporting for App Store Connect"
xcodebuild -exportArchive \
    -archivePath "$out/HotMess.xcarchive" \
    -exportOptionsPlist "$root/Configurations/ExportOptions-AppStore.plist" \
    -exportPath "$out/export" \
    -allowProvisioningUpdates

ipa="$out/export/HotMess.ipa"
[[ -f "$ipa" ]] || die "the export didn't produce $ipa"
[[ "$mode" == "export" ]] && { echo "==> Exported $ipa"; exit 0; }

# altool looks for AuthKey_<KEY ID>.p8 in ./private_keys among other places.
cd "$work"
echo "==> Validating"
xcrun altool --validate-app -f "$ipa" -t ios --apiKey "$key_id" --apiIssuer "$issuer_id"
echo "==> Uploading to TestFlight"
xcrun altool --upload-app -f "$ipa" -t ios --apiKey "$key_id" --apiIssuer "$issuer_id"
echo "==> Uploaded build $build_number. It shows in TestFlight once App Store Connect has processed it."
