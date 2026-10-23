# Hot Mess (iOS)

Nightlife app for finding venues, events and friends nearby.

The app was originally written in 2017 against Swift 3/4 with storyboards,
`UITableViewController` subclasses and callback-based networking. It has been
reworked into SwiftUI with Swift 6 concurrency; this file describes the shape of
the result.

## Requirements

- Xcode 16 or later (the project uses file-system synchronized folders,
  `objectVersion = 77`)
- iOS 18 deployment target
- Swift 6 language mode with complete strict-concurrency checking

Dependencies resolve through Swift Package Manager on first open:

| Package | Used for |
| --- | --- |
| [facebook-ios-sdk](https://github.com/facebook/facebook-ios-sdk) | Login |
| [Kingfisher](https://github.com/onevcat/Kingfisher) | Remote image loading and caching |
| [AudienceKit SDK](https://github.com/lwm-luminx/audience-kit-sdk) 0.21.0 | Sign-in, session, GraphQL and branding against the AudienceKit API |
| [Stripe](https://github.com/stripe/stripe-ios-spm) (`StripePaymentSheet`) | Paying cover at Stripe venues |
| [Square In-App Payments](https://github.com/square/in-app-payments-ios) (`SquareInAppPaymentsSDK`) | Paying cover at Square venues |

The app runs on iPhone and iPad.

## Layout

```
HotMess/
  App/            SwiftUI entry point, routing, deep links
  Models/         Codable value types for every API payload
  Networking/     APIClient, typed endpoints, configuration, errors
  Services/       Session, keychain, location, realtime chat, logging
  DesignSystem/   Shared rows, images, load states, theme
  Features/       One folder per screen: a view plus its view model
Configurations/   Per-environment .xcconfig files
HotMessTests/     Swift Testing suites (offline)
HotMessUITests/   Launch smoke test
```

Source files are picked up from the folder tree automatically — adding a file
does not touch `project.pbxproj`.

## Architecture

`AppModel` is the composition root. It builds the configuration, the API client,
the session store and the location provider once, and is injected into the view
hierarchy with `.environment(...)`. Each screen owns a small `@Observable`,
`@MainActor` view model that exposes a single `LoadState` value, so loading,
empty and failure states are handled the same way everywhere.

- **AudienceKit.** Hot Mess is an AudienceKit audience. `AppModel` builds one
  `AudienceKitClient` from the configuration. `SessionStore` runs Facebook
  Login and hands the token to `AudienceKitClient.signIn`, which sends
  `POST /v1/token` with the audience host, the build's Facebook app ID and
  the device, then keeps the credential the API answers (`token`, `userId`,
  `audienceId`, `role`, `endpoint`) in the keychain as a `KeychainCredentialStore`
  (`SessionStore.credentialStore`). Sign in with Apple and connecting Facebook
  are the app's own REST calls; their credential goes to the SDK with
  `adopt(credential:)`. The app never looks inside the token. When the API
  ends the session (401), the SDK drops the credential and `SessionStore`
  returns to the login screen, once, saying "Please sign in again". A realtime
  socket the server closes as `unauthorized` does the same (`AppModel`'s cable
  hands its token to `SessionStore.sessionRejected(token:)`); a 403 or a
  dropped connection doesn't. Errors are told apart by `AudienceKitError.code`
  (`UNAUTHENTICATED`, `NOT_FOUND`, `INVALID` with `fields`, …), never by
  message (`APIError.init(_:)`). The Venues and People tabs read the audience over
  GraphQL, and `BrandStore` fetches `/v1/branding` and drives
  `Color.hotMessAccent` and the tint.
- **GraphQL.** Every other screen also goes through the audience's GraphQL
  endpoint on the SDK. `HotMessAPI` holds the documents: location reports and
  "Now" (`reportLocation`), the closest locale, venue, event and person
  detail, a locale's events, RSVPs (`rsvpEvent`), Pings (`sendPing`,
  `joinPing`, `leavePing`, `endPing`, and `myPing`/`friendPings` on Now,
  and on venues' and events' `ping` mixin) and push registration (`registerDevice`, with the bundle
  ID and whether the build's `aps-environment` is the APNs sandbox).
- **Ping.** "I want to go out tonight": a Ping names tonight's events or
  venues in the user's locale (or none), reaches the user's friends (or
  friends of everyone in its circle) and clears at 5am. It's sent from the
  Now screen or "Ping here" on a venue or event, and friends answer with
  "I'm in", also from the `PING` push's `PING_JOIN` action. "Add contacts"
  in the send sheet picks people from the phone (the system picker, so no
  Contacts permission; numbers stay on the phone): once the Ping is sent the
  app signs a link to it (`shareLink(path: "/pings/<id>", lifetime: DAY)`)
  and opens Messages addressed to them, or the share sheet where the device
  can't text. `/pings/<id>?e=<token>` opens that Ping; a recipient who can't
  see it yet gets the invitation (`GET /v1/share/invitation`) and joins with
  `joinPing`'s `invitationToken`. The token is opaque. The documents alias fields to the snake_case keys the
  models decode, and failures map to `APIError`.
- **REST.** Only the client status (`GET /v1/status`, which says the oldest
  version of the app the API still serves) and the two sign-ins the SDK has no
  call for (`POST /v1/token/apple`, and `POST /v1/token` with `connect`) are
  still REST. `APIClient` sends them through the SDK.
- **Models.** Every payload is a `Sendable`, `Codable` struct. Dates accept both
  the API's `yyyy-MM-dd'T'HH:mm:ss.SSSZ` format and plain ISO 8601, and IDs that
  Facebook sends as either a string or a number decode from both.
- **Concurrency.** Services are actors or `@MainActor` types; there are no
  shared mutable singletons behind the UI.

## Environments

`Debug`, `Staging` and `Release` build configurations map to the three
`.xcconfig` files in `Configurations/`, which set the API host, the
AudienceKit audience host (`AUDIENCE_HOST`) and optional ID, the Facebook app
ID, bundle suffix and APNs environment. Four shared schemes select between
them.

| Configuration | API | Facebook app |
| --- | --- | --- |
| Debug | `http://localhost:3000` | development (842337999153841) |
| Staging | `https://api.next.audiencekit.com` | staging (1660272792277019) |
| Release | `https://api.audiencekit.com` | Hot Mess (1168782378316790) |

Release signs in with Hot Mess, a Consumer Facebook app, using classic Facebook
Login with only `public_profile` until App Review is approved. Email and friend
permissions are not requested. The
AudienceKit service app (713525445368431) does Page reads for the API and isn't used here.

The API only accepts a Facebook app that belongs to the audience named by
`AUDIENCE_HOST`. `hotmess.admin.audiencekit.com` resolves by subdomain; switch
to `hotmess.social` once that domain is verified.

`FACEBOOK_CLIENT_TOKEN` is intentionally empty in each configuration: copy the
client token for each environment out of the Facebook app dashboard
(Settings → Advanced → Client token). The Facebook SDK reports an error at
runtime while it is blank.

## Cover

When a venue takes cover in the app (`coverCharge.payable`), its page, the
event that sets tonight's cover, and Now (at the venue) offer "Pay cover".
`CoverCheckout` calls `buyCover`, which says who takes the venue's cover
(`provider`):

- **Stripe**: Stripe's PaymentSheet on the venue's connected account
  (`STPAPIClient.shared.stripeAccount`; Connect direct charges) with the
  platform's publishable key, then `confirmCover`.
- **Square**: Square's In-App Payments SDK with the audience's
  `squareApplicationId`. The buyer picks Apple Pay (when Square can take it on
  the device) or Square's card form; either makes a payment token that
  `payCover` charges to the venue's Square location.

Then it shows the pass. Passes live under Me → Passes.

The pass's QR code is made on the phone every 30 seconds from the pass's
secret (`CoverPass`, the API's `app/services/cover_pass.rb`), so it works with
no signal; a sliding colour band shows staff it's live. Scanning passes at the
door is Velvet's job (the separate staff app), not this app's.

Apple Pay uses `APPLE_PAY_MERCHANT_ID` (`merchant.social.hotmess`) from the
xcconfig files and the `in-app-payments` entitlement. Register that merchant
ID in the Apple Developer account and add an Apple Pay certificate for it on
Stripe; with the setting empty, both providers take cards only. Square venues
use the same merchant ID, which needs a payment processing certificate made
from Square's CSR (Square Developer Dashboard → the application → Apple Pay).
Apple encrypts each payment to one certificate per merchant ID, so if Stripe
and Square can't share it, give Square its own merchant ID.

## App icon

Each build configuration has one 1024×1024 universal icon with light, dark and
tinted appearances, coloured by build as the 2017 icons were: `AppIcon`
(Production, blue on white), `AppIconStaging` (Test, green) and
`AppIconDevelopment` (Development, purple). The mark is the figure from the
original login background (`Design/AppIcon/silhouette.svg`) printed slightly out
of register. They're rendered, not drawn by hand: edit
`Design/AppIcon/make_app_icon.py` and run `python3 Design/AppIcon/make_app_icon.py`
(needs cairosvg). It also writes SVG masters to `Design/AppIcon/masters/`.

## Tests

`HotMessTests` runs entirely offline: model decoding against inline fixtures,
endpoint URL construction, deep-link parsing, geometry and formatting. Run them
with any scheme, or:

```sh
xcodebuild test -scheme "HotMess Debug" -destination "platform=iOS Simulator,name=iPhone 17"
```

The previous suite authenticated against Facebook with a token committed to the
repository and then called the live API, so it could not run offline and could
not distinguish a regression from an outage.

There is no CI build: macOS runner minutes cost ten times Linux ones. Before merging,
build on a Mac from the AudienceKit checkout with `scripts/verify-apple.sh hotmess`
(see the AudienceKit README, "Verifying Apple targets"). What CI does run is
`.github/workflows/graphql-documents.yml`, which checks every GraphQL document in
`HotMess/` and `HotMessTests/` against the published consumer schema (see
[Validate your GraphQL documents](https://developer.audiencekit.com/api/validate-documents/)).
The dumps publish from the API's `main`, so while this app tracks `next` the step
is `continue-on-error`; locally, run the same check against
`api/schema.graphql` in an `audience-kit` checkout on `next`.

## App Review

Apple's reviewer signs in with a code, not a personal account:

- While the audience is in App Review, `GET /v1/token/review` answers
  `{"enabled": true}` and the login screen shows **Have an App Review code?**.
  Like every sign-in, it first needs the 18+ check and the terms. The code from
  the App Store Connect review notes goes to `POST /v1/token/review`, which
  signs in the designated reviewer account (`users.app_reviewer`). A wrong code
  is a 401, shown as an invalid code.
- Only that account gets `canPretendLocation`, which shows **Pretend I'm here**
  on a venue so the reviewer can try its chat from anywhere. No one else sees
  it in an App Store build. Cover and coat check go through the venue's real
  Stripe or Square payment; there is no demo charge.
- Age: on iOS 26 the app asks for the declared age range (an 18 gate, the
  `com.apple.developer.declared-age-range` entitlement). Under 18 blocks
  sign-in. Otherwise, or on older iOS, the person ticks "I confirm I am 18 or
  older". The device keeps the confirmation.

Test hooks (`-HotMessReviewMode`, `-HotMessUseNextAPI`, `HOTMESS_API_URL`,
`-HotMessSafetyDemo`, `-HotMessUITestKaraoke=`) only compile with the
`TEST_HOOKS` condition, set for Debug and Staging. Run the UI tests and the
Screenshots scheme on those, not on Release.

## TestFlight

`Scripts/testflight.sh` archives the "HotMess Release" scheme, exports it for
App Store Connect with `Configurations/ExportOptions-AppStore.plist`, and
uploads it with `xcrun altool`:

```sh
Scripts/testflight.sh                 # archive, export, validate and upload
Scripts/testflight.sh --export-only   # stop at build/testflight/export/HotMess.ipa
```

- **Signing:** automatic, with team `DWVXMLB45Y` and an Apple Distribution
  certificate.
- **Build number:** the minutes since 2026-01-01 UTC unless `BUILD_NUMBER`
  is set. Keep it under 2,147,483,647: the API stores it in a 32-bit column.
- **API key:** the upload uses the App Store Connect API key garage-rag
  uses. That's the login keychain item with service
  `me.rickmark.garage-rag.asc-api-key`, or `ASC_KEY_ID`, `ASC_ISSUER_ID` and
  `ASC_KEY_PATH`.

## Known follow-ups

- Sign-in requests only `public_profile` while App Review is pending. Revisit
  additional permissions after approval.

The shared Swift package is the public AudienceKit SDK, resolved from
`https://github.com/lwm-luminx/audience-kit-sdk.git` (formerly `audience-kit-sdk-swift`;
the repository now also holds the Kotlin Multiplatform core and the Android SDK on one
version). The project pins a revision, 0.21.0's release commit; once the SDK is tagged,
change the requirement in `HotMess.xcodeproj` to `upToNextMinorVersion`. Consumer
services come from `AudienceKit`; shared design tokens and UI come from
`AudienceKitUI`, both built on `AudienceCore`. The app's realtime cable is the SDK's
`AudienceCable`, which signs its handshake the way every call is signed
(`Authorization: Bearer`, `X-AudienceKit-API-Version`); `GraphQLCable` only reads the
subscription results.

## Shared App Group

Release retains `group.social.hotmess` and `group.com.audiencekit.shared`. Staging (scheme **HotMess Next**) uses bundle ID **`social.hotmess.HotMess.next`**, display name **Hot Mess Next**, private group **`group.social.hotmess.next`**, and the cross-app **`group.com.audiencekit.shared`**. The old staging installation remains separate. Debug keeps its existing development identity and entitlements.

Use `Scripts/testflight.sh --next` to archive and upload Next, or add `--export-only` to stop at export. Next artifacts go into `build/testflight-next`; the default command still archives Release into `build/testflight`. Distribution archives override `APNS_ENVIRONMENT=production` so the packaged runtime setting matches TestFlight push delivery. Direct Staging device builds keep development APNs.

The shared group is only for deliberate cross-app data, not environment-specific sessions, credentials, or databases. Staging calls the next preview (`api.next.audiencekit.com`), which runs new API code against production data; separate app identifiers and groups do not isolate backend records.

Portal setup: the Next ID and private/shared group assignments are registered. On October 9, 2026, Apple Pay Payment Processing (merchant.social.hotmess), Associated Domains, Push Notifications, Sign in with Apple (primary App ID), and Wallet were enabled and verified on `social.hotmess.HotMess.next`. Provisioning must include these capabilities; a signed archive/export and a separate App Store Connect app record are still needed before TestFlight distribution.

Verified on October 9, 2026: signed test builds of Focus, Velvet, Backstage, and Hot Mess were installed on the paired iPhone 15 Pro Max. Their signed entitlements and provisioning profiles include the shared group, and iOS reports the same shared container for all four.

## Next setup verification

On October 9, 2026, an unsigned generic-iOS Staging build of **Hot Mess Next** passed. Packaged values were checked: `social.hotmess.HotMess.next`, `https://api-staging.audiencekit.com`, staging API environment, and production APNs when built for TestFlight. The upload script passed shell syntax and mocked export-only checks for both production and Next, including separate output directories. No upload or signed-device validation was performed. The new App Store Connect record and OAuth provider registration for the new ID remain pending. Portal capabilities are now enabled as recorded above; this does not verify payment processing, push delivery, associated-domain files, or end-to-end sign-in.

## App Clip

`HotMessClip/` shows the record behind a shared `hotmess.social` link and takes one
payment with Apple Pay. Design: `docs/APP_CLIP.md`; the screens as built:
`docs/APP_CLIP_REWORK.md` (mockups linked there).

| Link | The one action | Hand-off to the app |
| --- | --- | --- |
| `/venues/<uuid>` | Pay tonight's cover, or show the pass already held | Who's out, chat |
| `/events/<uuid>` | Pay the venue's cover for tonight (not an event ticket) | RSVP, lineup, chat |
| `/people/<uuid>` | Tip the performer (preset chips or another amount) | Follow, posts |
| `/pings/<uuid>?e=…` | Read the invitation | Join the Ping (the token rides into the app) |

Every screen is built on the Hot Mess preset of the AudienceKit design system, with
the tokens fixed in `ClipTheme.swift` (the clip doesn't link AudienceKitUI). Public
basics come from `GET /v1/share`; Ping invitation details come from
`GET /v1/share/invitation`, which requires an opaque signed `e` capability and is
private, no-store and noindex. Everything else (prices, tiers, tip presets, the pass)
is GraphQL and needs a session, so tapping Apple Pay without one shows Sign in with
Apple first, with one consent sentence (18+, Terms, Privacy) and the Declared Age
Range check. A public clip view and guest checkout are API follow-ups; when they
land, the sign-in step moves after the payment, as the design intends.

Payments are Apple Pay only, through `StripeApplePay` (`ClipCheckout.swift`):
`buyCover`/`startTip` open a PaymentIntent on the venue's or performer's Stripe
account, `STPApplePayContext` confirms it, and `confirmCover`/`confirmTip` check it
with Stripe. Square venues and performers pay in the full app. The Stripe payment
sheet and the Square SDK are not linked into the clip (15 MB door-code budget), so
`CoverCheckout.swift` is app-only; the clip compiles the shared models,
`CoverPass` (rotating QR), `AgeGate` and `SharedAuthentication`.

Sharing a Ping authorizes its recipient to join, including someone outside the
existing friend graph. It does not join them on opening the link: the clip shows the
invitation and offers the app, and the app's `AppRoute.ping(_, invitation:)` joins it
after install, since iOS hands the clip's invocation URL to the full app. The
authenticated join mutation checks expiry, the inviter's continued access, bans and
blocks. Ending the Ping invalidates its invitations. The preview includes the note
and selected places, never the circle of attendees. Forwarding the link also
forwards its invitation authority.

Native venue, event and Ping share buttons obtain an expiring, attributed link
before presenting the iOS share sheet. There is no unsigned fallback if link
creation fails. The main app retains and verifies the invitation when opening it.

`SKOverlay.AppClipConfiguration` offers the full app from every Get Hot Mess button,
the pass and the tip receipt. The Clip stores credentials separately. On
installation, iOS makes the Clip's keychain available to its corresponding parent
app; the parent migrates that credential once, ahead of an older parent credential.
This is a Clip-to-app handoff, not bidirectional keychain sharing. Account sign-in
and server-side ban checks are the current authenticated fallback. App
Attest/DeviceCheck verification is not implemented, and no installation identifier
is treated as ban evidence.

Two targets share the source: `HotMessClip` embeds in `HotMess`, and
`HotMessNextClip` embeds in `HotMessNext`.

| Configuration | Clip bundle ID |
| --- | --- |
| Debug | `social.hotmess.HotMessDevelopment.Clip` |
| Staging / Next | `social.hotmess.HotMess.next.Clip` |
| Release | `social.hotmess.HotMess.Clip` |

Open `HotMessClip` (Debug/local API) or `HotMessNextClip` (Staging/Next API).
Replace the zero UUID in `_XCAppClipURL` with a real invocation link. The zero UUID
is intentionally a missing-record test. Versions must stay aligned with the parent.
Run the standalone parser and tip-amount checks with `Scripts/test-app-clip.sh`.

Deploy the API invitation contract before distributing these clients. The website's
AASA source now lists all three Clip application IDs. It must be served as JSON on both apex and www without a
redirect; source changes alone do not update Apple's cached association.

Before distribution, register each Clip under its matching parent, configure Apple
sign-in and Apple Pay capabilities and profiles, and configure Advanced App Clip
Experiences in App Store Connect for venue, performer, Ping and event invocation
URLs. Verify invocation, authentication handoff, provider payments, and the final
thinned Clip size on signed physical-device builds. Simulator compilation cannot
validate those deployment requirements. Next remains TestFlight-only; follow
`docs/development/IOS_DISTRIBUTION.md` and the release skill for archives/uploads.

Apple references: [website association](https://developer.apple.com/documentation/appclip/associating-your-app-clip-with-your-website)
and [Clip-to-app data sharing](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app).
