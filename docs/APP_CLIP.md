# Hot Mess App Clip for rich shares

> Exported on 2026-10-17 from the design doc https://claude.ai/code/artifact/ce83d466-60c7-4eaf-933a-213ac451ab2b. Owner thread: "App Clip for rich shares". Builds on `api/doc/DEEP_LINKS.md` (audience-kit) section 3. Design only; nothing is built yet.

**Recommendation:** build one App Clip, `social.hotmess.HotMess.Clip`, as the landing for every shared venue, event and person link on an iPhone without Hot Mess. Phase 1 shows the record and lets someone pay tonight's cover with Apple Pay after Sign in with Apple; door App Clip Codes come in phase 2 on the same target, so the clip is budgeted at 15 MB from day one.

## Fit

The clip is worth building because a shared link's second tap is where Hot Mess loses people today: on an iPhone without the app, the link opens a web page that can only show the record and a Smart App Banner, and anything that needs an account (paying cover, RSVP) ends at the App Store. With the clip, that tap opens a native card in Messages or Safari in a few seconds, shows the venue or event, and lets the person pay tonight's cover with Apple Pay without installing anything. The first impression still comes from the preview tags (hotmess.social #23 and audience-kit #317); the clip is what happens after.

| Recipient | Today | With the clip |
| --- | --- | --- |
| iPhone, Hot Mess installed | Universal link opens the screen in the app (works, including after sign-in) | Unchanged: the full app always wins over the clip |
| iPhone, no Hot Mess | Web page in Safari with a Smart App Banner; cover and RSVP need the App Store first | App Clip card, then the record, Apple Pay cover, and a Get prompt that lands them signed in |
| Android | Web page with a Play banner (App Links verify once assetlinks.json ships) | Unchanged: Google retired Play Instant, there is no equivalent |
| Desktop or a crawler | Web page and the preview tags | Unchanged |

What the clip can't do, by design: friends, Here now, chat, Pings and anything else about members. Those stay in the full app, so a shared Ping link in the clip can only say "Open in Hot Mess". The cost is a new Xcode target that ships with an app release, a size discipline, and App Store Connect setup: roughly a release cycle of Mac work on rickmark-m3.

## Limits that shape the design

The one decision the limits force is size: a clip that may ever be launched from an App Clip Code, QR code or NFC tag at a door has to stay under 15 MB uncompressed, while a link-only clip on iOS 17+ may go to 100 MB. Hot Mess's deployment target is iOS 18, so the OS tiers below 17 don't matter, but the door codes do. Keeping the 15 MB budget means leaving the Facebook SDK, Kingfisher, Square and Stripe's full payment sheet out of the clip. Figures are from Apple's [Choosing the right functionality for your App Clip](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip).

| Limit | Value | Effect on the design |
| --- | --- | --- |
| Uncompressed size, physical invocations (App Clip Code, QR, NFC) | 15 MB | The budget, measured per device variant with Xcode's App Thinning Size Report |
| Uncompressed size, digital invocations only (links, Safari, Spotlight), iOS 17+ | 100 MB | Not used: taking it rules out door codes for good |
| App Clip demo link | 100 MB and physical codes | For a game demo, not for us |
| Frameworks with no runtime function | EventKit, Contacts, PhotoKit, CoreMotion, Messages, MessageUI, BackgroundTasks, HealthKit and others | No "Add to calendar" in the clip; it is offered in the full app |
| Background work | No background URLSession, no Background Modes, no Bluetooth while not in use | Nothing to do; the clip is foreground only |
| Device identity | `identifierForVendor` and device name return empty strings | `registerDevice` and error reports must accept an empty identifier |
| Location | When-in-use only; the grant resets at 4 a.m. the next day | Enough for "you're here" and for door-code location confirmation |
| Notifications | Ephemeral, 8 hours after each launch, on by default from the card; push works with a `target-content-id` URL | Door and pass notices for the night, nothing longer |
| Payments | Apple Pay works; in-app purchase is reserved for the full app | Cover is a physical-admission purchase under guideline 3.1.3(e), so Apple Pay is right anyway |
| Sign-in | Sign in with Apple works; ASWebAuthenticationSession works | Apple only in the clip; Facebook Login's SDK is dropped for size and is unverified in clips |
| Data sharing | Only with the parent app, through an app group and a keychain access group | Hands the session and small state to the full app on install |
| Tracking | No AppTrackingTransparency, no SKAdNetwork | None used today |
| Face ID | Not available | Not needed |
| App Review | The clip is reviewed with the app and carries its age rating | The age gate from the app applies before paying cover |

## Invocation

Share links need only the default experience plus the associated domain: once hotmess.social's link file lists the clip under `appclips`, a `https://hotmess.social/venues/<id>` link tapped in Messages or opened in Safari on iOS 16.4+ shows the App Clip card with the full URL as the invocation URL. Advanced experiences in App Store Connect are needed only for App Clip Codes and Maps, so they belong to phase 2 (one per venue, created through the App Store Connect API when a venue turns door codes on). The table is from Apple's [Configuring the launch experience of your App Clip](https://developer.apple.com/documentation/appclip/configuring-the-launch-experience-of-your-app-clip).

| How the link is opened | Phase | What it needs |
| --- | --- | --- |
| Link tapped in Messages (iMessage preview, then the clip card) | 1 | AASA `appclips` entry, default experience; the Worker's preview tags make the bubble rich |
| Share link opened in Safari (banner, or full card) | 1 | `apple-itunes-app` meta with `app-clip-bundle-id`; `app-clip-display=card` on share pages so the card opens on load |
| Link opened from any other app (Instagram, Facebook, WhatsApp, Mail) | 1 | Same as Messages: the system shows the card for an associated link |
| Spotlight, Siri Suggestions | 1 | Default experience; location suggestions need an advanced experience |
| Full app installed | always | Nothing: the universal link opens the app; the clip never runs |
| QR code (printed flyer, table card) | 2 | Encodes the share URL; default experience is enough, 15 MB budget applies |
| App Clip Code at the door, NFC tag | 2 | Advanced experience per URL (`/venues/<id>`), code generated in App Store Connect or with `AppClipCodeGenerator`; location confirmation |
| Apple Maps place card | 2 | Advanced experience tied to the venue's Apple Maps place |
| Default App Clip link `https://appclip.apple.com/id?p=social.hotmess.HotMess.Clip&…` | optional | Generated by App Store Connect; useful for a QR before the domain is associated, not needed once it is |

Two details: the invocation URL is the share link itself, so the clip reuses the app's `DeepLink` parser; and the Worker already writes the Smart App Banner's `app-argument`, so the extra attributes are a one-line change in `edge/src/shareCard.ts` and `src/layouts/Base.astro`.

## What the clip shows per share type

Every screen opens from one public read with no sign-in, so the record is on screen in the time the card takes to dismiss; the one action that needs an account asks for Sign in with Apple at the moment it is tapped, never before. The public read is the share card the API already serves (`GET /v1/share`, audience-kit #317) widened with a `clip` view: address and map coordinates, tonight's events with cover price and hours, an event's lineup and hosts, a performer's upcoming listings, the ticket partner link, and the venue's payment provider (Stripe or Square). It stays public data only, by the same rules as the card: never members, tribes, counts, chat or presence.

| Shared link | The clip shows | One action (Apple Pay or sign-in) | Hands to the full app |
| --- | --- | --- | --- |
| `/venues/<id>` | Photo, name, locale, address with Open in Maps, tonight's and this week's events, cover price and hours | Pay cover with Apple Pay (Stripe venues); the pass with its rotating QR appears on screen | Here now, chat, friends; Square venues get "Pay in the app" |
| `/events/<id>` | Flyer, name, day and time in the venue's zone, venue, hosts and lineup, Canceled state, description | Pay cover, or Get tickets (partner link in an in-clip Safari view) | RSVP, Ping friends, add to calendar (EventKit is unavailable in clips) |
| `/people/<id>` | Photo, name, where they're featured, upcoming shows | Open a show (stays in the clip) | Follow, chat |
| `/pings/<id>`, `/venues/<id>/chat`, `/locales/<id>/chat` | A branded "This is for friends on Hot Mess" screen with the venue or locale named when the link carries one | none | Everything: Get Hot Mess is the only button |
| `/`, `/app/*`, unknown paths | The default card copy and a Get Hot Mess prompt | none | Everything |

Every screen ends with the full-app prompt placed under the content, after the action, as Apple's App Clip design guidance asks: the clip finishes the task first, then offers the app. There is no tab bar, no settings and no search; a link opens one record and its children (an event from a venue, a show from a performer), which is why the clip stays small.

## Flow

```
Tap a share link ──▶ Hot Mess installed? ──yes──▶ Full app opens the screen (universal link, as today)
                            │ no
                            ▼
                     App Clip card ──▶ Venue, event or person (public read, no sign-in)
                                                 │ Pay cover tapped
                                                 ▼
                                       Apple sign-in, Apple Pay (Stripe venues; pass on screen)
                                                 │ task done
                                                 ▼
Signed in, same screen ◀── Full app installs ◀── Get Hot Mess (SKOverlay under the content)
(no second sign-in)        (reads the shared keychain)
```

With the app installed the link never reaches the clip. Without it, the record is on screen before any sign-in; Pay cover is the only step that asks for Sign in with Apple, and the Get prompt comes after the task, with the session already in the shared keychain for the full app.

## Sign-in and handoff

Sign in with Apple is the clip's only sign-in, asked for at the moment someone taps Pay cover, and the credential it earns is the same session the full app uses, so installing the app never asks them to sign in again.

- **Apple only.** The clip calls the API's `POST /v1/token/apple` as the app does today (`SessionStore.signInWithApple`) and adopts the credential into the SDK session. Facebook Login stays in the full app: its SDK is most of the size budget and its clip behaviour is undocumented. Someone whose Hot Mess account is Facebook-only gets a second account only if Apple hides their email; the app's existing "connect Facebook" flow lets the Facebook account take over the Apple sign-in afterwards, so that case heals in the full app.
- **Shared keychain.** The clip and the app share a keychain access group (`$(AppIdentifierPrefix)social.hotmess.HotMess$(BUNDLE_SUFFIX)`) and the existing app group (`group.social.hotmess`, `.next` for staging). The SDK's `KeychainCredentialStore` is pointed at that group in both targets, so the credential the clip saved is what the app reads at first launch. The app group carries the small state: age gate acknowledged, the last invocation URL, a flag that a pass was bought tonight.
- **The prompt.** `SKOverlay` with `AppClipConfiguration(position: .bottom)` appears under the content once the screen has loaded or the pass is on screen, dismissible. On install from that overlay the system launches the full app with the clip's invocation URL as its user activity, which `HotMessApp`'s `onContinueUserActivity` already routes, so the person lands on the venue or event they were looking at, signed in.
- **Passes.** The admission belongs to the account on the server, so the pass shows in the full app's passes list without any transfer; the shared flag only lets the app bring it to the front on first launch.
- **Permissions.** Location is asked for only when it adds something (a venue's distance, phase 2 door confirmation); Apple carries camera, microphone and Bluetooth grants over to the full app, location is re-asked.
- **Review.** Guideline 4.0 for App Clips: no sign-in before the content, no account creation that isn't needed for the task, the Get prompt only after the task.

## Build

The clip is a new `HotMessClip` target in HotMess.xcodeproj, bundle `social.hotmess.HotMess$(BUNDLE_SUFFIX).Clip`, so the three existing configurations give `social.hotmess.HotMess.Clip`, `social.hotmess.HotMess.next.Clip` and `social.hotmess.HotMessDevelopment.Clip` with no new xcconfig. It links the open-source SDK (`AudienceCore`, `AudienceKit`, `AudienceKitUI`) and Stripe's `StripeApplePay` module, which Stripe publishes for App Clips, and nothing else from the app's package list. Screens are shared with the app by target membership of the detail views and `DeepLink`, not by linking the app; `AsyncImage` replaces Kingfisher inside the clip.

| Where | Change | Size |
| --- | --- | --- |
| hot_mess_ios | `HotMessClip` target, `NSAppClip` keys (ephemeral notifications on), entitlements: `appclips:hotmess.social`, Apple Pay merchant, app group, keychain access group shared with the app; the app's entitlements gain the keychain group and `com.apple.developer.parent-application-identifiers` on the clip | medium |
| hot_mess_ios | Clip views: landing per link kind, cover with `PKPaymentAuthorizationController` via `StripeApplePay`, pass view reusing the SDK's `CoverPass` code, Sign in with Apple button, `SKOverlay` | medium |
| hot_mess_ios | `registerDevice` and error reports tolerate an empty device identifier; the age gate reads and writes the shared app group | small |
| audience-kit (API) | `GET /v1/share?view=clip` (or `/v1/clip`) adding address, coordinates, tonight's events with cover price and hours, lineup and hosts, upcoming listings for a person, ticket link, payment provider; same five-minute public cache | small |
| audience-kit (API) | Cover purchase already works for a signed-in Apple account over GraphQL; a `confirmCover` path that takes a Stripe payment method id from Apple Pay, if `buyCover`'s Stripe step needs it without the payment sheet | small, to verify |
| hotmess.social | AASA: `"appclips": { "apps": [ "DWVXMLB45Y.social.hotmess.HotMess.Clip", "…next.Clip", "…HotMessDevelopment.Clip" ] }`; banner meta gains `app-clip-bundle-id=social.hotmess.HotMess.Clip` and, on share pages, `app-clip-display=card`; the Worker writes the same | small |
| App Store Connect | Default experience: 1800×1200 header image, subtitle under 56 characters ("Who's out tonight, and where"), verb Open; ships with the next app version | small |
| App Store Connect, phase 2 | Advanced experiences per venue `/venues/<id>` created by the API through `POST /v1/appClipAdvancedExperiences`; App Clip Codes rendered for the admin venue page | medium |

The size budget is checked before any design work is spent on it: archive the clip on rickmark-m3 and read the App Thinning Size Report's uncompressed figure for the clip variant. The SDK, SwiftUI and PassKit should sit well under 15 MB; `StripeApplePay` is the only dependency with weight, and if it alone breaks the budget the fallback is PassKit straight to the API with Stripe's `PaymentMethod` created server-side from the Apple Pay token. Verification follows the Apple rule: no macOS CI, `scripts/verify-apple.sh hotmess` on the Mac before merge.

## Phases and open questions

Phase 1 ships with the app release after 2.0.1 clears review, once the preview Worker is deployed (it is the first impression the clip depends on). Phase 2 reuses the same target.

1. **Phase 0, a day on the Mac.** Empty clip target linking the SDK and `StripeApplePay`; archive; read the size report. Go or change the payment dependency.
2. **Phase 1, shares.** API `clip` view; AASA and banner changes; clip screens for venue, event, person and the friends-only landing; Sign in with Apple; Apple Pay cover at Stripe venues; shared keychain and SKOverlay handoff; default experience in App Store Connect; TestFlight (clips test through the app's TestFlight build and the App Clip demo link).
3. **Phase 2, the door.** Advanced experiences per venue through the App Store Connect API, printable App Clip Codes on the admin venue page, location confirmation (`APActivationPayload.confirmAcquired(in:)`), ephemeral door notifications, Square venues if Square's SDK can be avoided.
4. **Later.** Platform clips for other audiences' apps (each tenant app ships its own clip; the per-host AASA from the deep links plan lists it), Apple Maps place experiences, Live Activity for a pass.

Open for Rick (phase 1 scope approved 2026-10-17):

- [x] Phase 1 scope approved by Rick on 2026-10-17: view plus Apple Pay cover, with Sign in with Apple only. This replaces the "door check-in or view-only" question from the deep links thread; door codes become phase 2 on the same clip.
- [ ] Keep the 15 MB budget (recommended) so door codes stay possible, or take the 100 MB link-only tier and give them up.
- [ ] Default experience copy and header image (the Hot Mess brand frame from the share previews can be reused).
- [ ] Whether RSVP belongs in phase 1 once someone has signed in for cover, or stays in the full app (recommended: full app, keeps the clip to one action).

## Sources

- Apple, [Choosing the right functionality for your App Clip](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip): size tiers, unavailable frameworks, data restrictions.
- Apple, [Configuring the launch experience of your App Clip](https://developer.apple.com/documentation/appclip/configuring-the-launch-experience-of-your-app-clip): default and advanced experiences, invocation table, URL prefix matching, card text limits.
- Apple, [Enabling notifications in App Clips](https://developer.apple.com/documentation/appclip/enabling-notifications-in-app-clips): 8-hour ephemeral window, `target-content-id`.
- Apple, [App Clips and App Clip experiences](https://developer.apple.com/documentation/appstoreconnectapi/app-clips-and-app-clip-experiences) (App Store Connect API) and the [forum thread on creating advanced experiences](https://developer.apple.com/forums/thread/783676).
- Deep links thread plan: `api/doc/DEEP_LINKS.md` in audience-kit, [hotmess.social #23](https://github.com/lwm-luminx/hotmess.social/pull/23), [audience-kit #317](https://github.com/lwm-luminx/audience-kit/pull/317), `api/doc/SHARE_CARDS.md`.
- Repo files read: hot_mess_ios `HotMess/App/AppRoute.swift`, `HotMess/App/HotMessApp.swift`, `HotMess/HotMess.entitlements`, `Configurations/*.xcconfig`, `HotMess/Services/SessionStore.swift`, `HotMess/Services/CoverCheckout.swift`; audience-kit-sdk-swift `Package.swift`, `Sources/AudienceKit/CoverPass.swift`; audience-kit `api/app/controllers/token_controller.rb`, `api/app/controllers/graphql_controller.rb`, `api/doc/DIGITAL_COVER_CHARGE.md`; hotmess.social `public/.well-known/apple-app-site-association`, `src/layouts/Base.astro`, `edge/src/shareCard.ts`.
- Not verified: that Stripe's `StripeApplePay` module fits the budget and that the Facebook SDK behaves in a clip; both are checked in phase 0.
