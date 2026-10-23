# Hot Mess App Clip: rework of the codex build

> Written 2026-10-23 in the thread "App Clip for rich shares". Mockups: https://claude.ai/artifact/Whf1HPqtA1StbyrKWZv9dB (Design canvas, 13 phone screens, AudienceKit design system with the Hot Mess preset). Design basis: `docs/APP_CLIP.md` (phase 1 scope approved by Rick on 2026-10-17: view plus Apple Pay cover, Sign in with Apple only). Code reviewed: `HotMessClip/` as merged to `next` by hot_mess_ios #153 (codex commit `4f76d84` "Add CTA-first Hot Mess App Clip and signed Ping sharing").

**Summary.** The codex clip is a working skeleton with the right bones: a strict `ClipLink` parser, a clip-to-app keychain handoff, the rotating pass QR and a `CoverPaymentAPI` protocol that keeps `CoverCheckout` shared with the app. What it lacks is the product: it is unbranded (system blue, a large title and one button), it asks for two consent toggles and a sign-in before any payment, it offers RSVP and Ping joins the approved scope leaves to the full app, it never offers the full app at all, and it links the Stripe PaymentSheet and the Square SDK, which puts the 15 MB door-code budget at risk. The mockups redraw the same flows on the Hot Mess design system and narrow the clip to one job: show the record, take tonight's cover or a performer's tip with Apple Pay, hand the person to the app. (Tipping was added back on 2026-10-23 at Rick's request on the mockups.)

## What the codex build does (as merged)

| Piece | What it is | Keep? |
| --- | --- | --- |
| `ClipLink.swift` | Strict parser: https only, `hotmess.social` or `www`, two path segments (`venues`, `events`, `people`, `pings`), a UUID, at most one `e` query (the signed invitation) | Keep as is |
| `HotMessClipApp.swift` `ClipView` | Loads `GET /v1/share` or `/v1/share/invitation`, shows `card.title` in `.largeTitle.bold()`, one primary button chosen by `ClipAction.primary(for:)`, description, `AsyncImage`, Sign out; error and "This link isn't supported" states | Replace the layout; keep the loading model |
| `ClipAction` | venues: Pay cover; events: RSVP (plus Pay cover); people: Tip; pings: Join Ping | Keep Pay cover and Tip; RSVP and Join hand off |
| `ClipSession.swift` | SDK client with `HotMessAuthentication.clipStore`, Sign in with Apple then `acceptTerms`, a random `ClipInstallationID` in UserDefaults, `CoverCheckout` with `.systemBlue` tint and the Stripe redirect URL | Keep the session and installation id; change the order (pay first, sign in after) and the tint |
| `ClipActionSheet.swift` `ClipSignInView` | Two toggles ("I am 18 or older", "I accept the Terms and Privacy Policy"), links, `SignInWithAppleButton`, `AgeGate.requestDeclaredAge` | Replace with one sentence of consent under the button; keep the Declared Age Range call |
| `ClipCoverViews.swift` | Tier picker, "Pay cover \(price)", `ClipPassView` rotating QR via CoreImage | Keep the pass; restyle the picker |
| `ClipPerformer.swift` `ClipTipCheckout` | Tips through the Stripe sheet or Square | Keep; move to Apple Pay only, restyle as the tip sheet (screen 13) |
| `ClipAPI.swift` | GraphQL `ClipVenue`, `ClipEvent`, `ClipPerformer`, `buyCover`, `buyCoatCheck`, `payCover`, `confirmCover`, `refundAdmission` | Keep cover, tips and refund; drop coat check from the clip target |
| `SharedAuthentication.swift` `ClipCredentialHandoff` | Clip keychain service `social.hotmess.account.clip`, migrated once into `social.hotmess.account` on first app launch | Keep |
| `SignedShareButton`, `ShareInvitation`, `SharedPingScreen`, `AppRoute.ping(_, invitation:)` | Signed, expiring share links (`shareLink(path:, lifetime:)`, DAY/WEEK/MONTH) and the app side of a Ping invitation | Keep; the clip shows the invitation, the app joins it |
| Entitlements and Info.plist | `appclips:hotmess.social` (+www), Apple sign-in, declared age range, in-app payments, on-demand install, parent application identifiers; `NSAppClipRequestEphemeralUserNotification` false, location confirmation false | Keep; add the app group and keychain access group the design names; notifications and location stay off in phase 1 |
| Dependencies linked into the clip | AudienceKit SDK, `StripePaymentSheet`, `SquareInAppPaymentsSDK` | Replace the two payment SDKs with `StripeApplePay` (or PassKit straight to the API) before measuring the size |

## What the mockups change, screen by screen

Numbers match the artboard titles on the canvas.

1. **App Clip card.** The system card over the Messages thread, with Hot Mess's header image (venue photo, spectrum ribbon, "Neighbors tonight"), the app name and the one-line subtitle "See what's on and pay cover. No download." The image and subtitle are App Store Connect's default experience; per-venue titles come with phase 2's advanced experiences.
2. **Venue.** The app's HeroHeader (256 photo, glass pills for "Open now · until 2am" and "21+", display title), then a "Cover tonight" card with the price and a black Apple Pay button, "On tonight" rows with the date tile, a social line that names counts only (no members), and a grey "Get Hot Mess" footer. Codex: title, one blue button, description, image.
3. **Event.** Same shell with the caps date overline, a cover card that lists the tiers and a "Few left" warning badge, the lineup with avatars, and "Get Hot Mess to RSVP" as the footer. RSVP stays in the app (design doc recommendation; codex put it in the clip).
4. **Performer.** Blurred-photo hero with the bio, a "Tip Betty" card with $5/$10/$20/Other chips and an Apple Pay button, "Next up" linking to tonight's event (cover is paid there), and "Get Hot Mess to follow Betty". Codex: a Tip button that opened the Stripe sheet.
5. **Ping invitation.** The friends-only landing from the design doc, made concrete: the inviter's avatar in a spectrum ring, their message, the venue card with cover, a "Tell Alex you're in" panel that explains joining happens in the app, and a footer that says only recipients of the link can open it. Codex joined the Ping from the clip with the `e` token; here the token rides into the app through the handoff.
6. **Pick a tier.** Sheet over the venue: radio rows for General, Skip the line and Pay it forward, a fee breakdown, Apple Pay button, refund and terms line. Codex had a bare picker and "Pay cover $10".
7. **Keep the pass.** Shown after Apple Pay succeeds, not before: "You're on the list", Sign in with Apple, "Not now, show my pass", and one consent sentence (18+, Terms, Privacy) in place of the two toggles. Hide My Email is called out as fine. Skipping sign-in keeps the pass on the device and it still migrates to the app.
8. **Pass.** Dark screen for the door: spectrum stripe, the rotating QR with a "refreshes in 22s, screenshots won't scan" line, tier, guest, validity, door rule, Add to Wallet and Refund, and a "Keep this pass in Hot Mess" row. Codex: the QR and a label.
9. **Get Hot Mess.** `SKOverlay` with `AppClipConfiguration(position: .bottom)` over a "what's waiting in the app" card (pass carries over, who's out and chat, the week's calendar). Codex had no handoff prompt.
10. **Expired.** A signed invitation that has run out: what happened, "ask Alex for a fresh one", the venue card with "See tonight at Neighbors" and "Get Hot Mess". Codex showed a generic error alert.
11. **Unsupported.** Chat, locale and unknown links: "That one's in the app", a Get Hot Mess card, a hotmess.social fallback and one nearby row so the screen is not a dead end. Codex: `ContentUnavailableView("This link isn't supported")`.
12. **Loading.** Skeleton in the shell's shapes with the Hot Mess header pill from the first frame, so the clip never shows a blank white screen while `/v1/share` answers.
13. **Tip.** Sheet over the performer: amount chips ($5, $10, $20, $50), another amount, an optional note, "Show Betty my first name" on by default, Apple Pay, and "tips aren't refundable". Then the same Keep-the-pass sign-in offer as cover (screen 7) with the tip receipt in place of the pass.

## Rules the mockups follow

- **One action per screen, and it is Apple Pay.** Cover on venues and events, a tip on performers. RSVP, Ping join, coat check and follows are not in the clip. Each is named on the screen that would have had it, as the reason to get the app.
- **Pay first, sign in after.** App Clip guideline 4.0: no sign-in before the content or the task. Apple Pay carries the person's identity for the payment; Sign in with Apple is offered to keep the pass, and can be skipped.
- **Public data only.** Counts and "friends of the sender" lines are fine; names, presence, chat and tribes are not. The `/v1/share` card plus the `clip` view from the design doc is the whole data source.
- **Brand from the first frame.** The Hot Mess header pill (audience mark plus name), the spectrum as a ribbon or ring only, `accent` for the one Hot Mess button per screen, black for Apple Pay, white cards with `radius-photo` (26) on the `surface` wash, Figtree type scale (`display` once per screen, `heading` on cards, `body-sm` for metadata).
- **Every screen ends with the app.** The footer or SKOverlay is under the content, after the task, never before it.
- **Expiring links are invitations only.** Venue, event and performer links never expire. The expired state says so.

## Code changes implied

| Where | Change | Size |
| --- | --- | --- |
| hot_mess_ios `HotMessClip` | Remove `StripePaymentSheet` and `SquareInAppPaymentsSDK` from the clip target; add `StripeApplePay` (or PassKit to the API); archive on rickmark-m3 and read the App Thinning Size Report before any UI work | small, blocks the rest |
| hot_mess_ios `HotMessClip` | Replace `ClipView` with the shell above: hero, cover card, rows, footer; per-kind content from `ClipLink.kind`; `AsyncImage` stays | medium |
| hot_mess_ios `HotMessClip` | Reorder `ClipSession`: Apple Pay before Sign in with Apple; `ClipSignInView` becomes the "Keep the pass" screen with one consent sentence; keep `AgeGate.requestDeclaredAge` | small |
| hot_mess_ios `HotMessClip` | Add `SKOverlay` after the pass is on screen and on every Get Hot Mess button; carry the invocation URL and the `e` token in the app group so the app lands on the same record and joins the Ping | small |
| hot_mess_ios `HotMessClip` | Remove the Join Ping and RSVP actions and `buyCoatCheck` from the clip target (they stay in the app); `ClipTipCheckout` moves to Apple Pay through `StripeApplePay` and gets the amount chips, note and name toggle | small |
| hot_mess_ios `HotMessClip` | Expired, unsupported and loading states as drawn; `ClipPassView` gains tier, guest, validity and the refund button | small |
| hot_mess_ios `HotMess` | Entitlements: keychain access group and app group shared with the clip (the merged build shares a keychain service, not a group) | small |
| audience_kit_api | `GET /v1/share?view=clip` (address, tonight's events with cover and hours, lineup, upcoming listings, payment provider), per `docs/APP_CLIP.md`; cover tiers and "few left" come from the existing cover mutations' data | small |
| hotmess.social | AASA `appclips` entry and banner meta, unchanged from the design doc | small |
| App Store Connect | Default experience: header image, subtitle "See what's on and pay cover. No download." (46 characters), verb Open | small |

## Built (2026-10-23, hot_mess_ios PR #156)

The clip on this branch is the mockups in code, with one ordering change forced by the API.

| File | What it is |
| --- | --- |
| `HotMessClipApp.swift` | `ClipRootView`: loads `/v1/share` (or the invitation), then shows loading, the record, expired, unsupported or failed; owns the checkout sheet and the `SKOverlay` |
| `ClipLanding.swift` | Hero from the share card, the cover card (venues, events), the tip card (performers), the invitation panels (Pings), the Get Hot Mess footer, and the loading, expired, unsupported and failed screens |
| `ClipSheets.swift` | The sheet: sign in, tier picker, tip picker (chips, another amount, live quote), the dark pass with the rotating QR and refund, the tip receipt |
| `ClipCheckout.swift` | Apple Pay through `StripeApplePay` (`STPApplePayContext` on the venue's or performer's connected account), then `confirmCover`/`confirmTip`; Square venues are told to pay in the app |
| `ClipTheme.swift` | The Hot Mess preset tokens as fixed colors, the panel, pills, chips, button styles and the Apple Pay button |
| `ClipAPI.swift`, `ClipSession.swift`, `ClipLink.swift`, `ClipTipAmounts.swift` | GraphQL documents and models, the session and Sign in with Apple, the link parser, and the tip-amount rules checked by `Scripts/test-app-clip.sh` |
| `HotMess.xcodeproj` | Both clip targets link `AudienceKit` and `StripeApplePay` only; `StripePaymentSheet`, `SquareInAppPaymentsSDK`, the Square framework phase and `CoverCheckout.swift` are out of the clip |

Where the build departs from the mockups:

- **Sign in comes before the payment, for now.** Prices, tiers, tip presets, `buyCover` and `startTip` are GraphQL behind a session; only the share card is public. Tapping Apple Pay without a session shows the sign-in step (one consent sentence, Declared Age Range, Hide My Email welcome) and then the picker. The "Keep the pass" screen (7) returns when the API has a public clip view and guest checkout; follow-up filed on the API repo.
- **Tip note and "show my first name" are not sent.** `startTip` takes a person and an amount; the tip goes with the signed-in first name. Both fields wait on the API.
- **Add to Wallet, "few left" and "Pay it forward"** are not built: the first needs a pass type and signing certificate, the second needs capacity from the API, the third is a venue tier if the venue defines one (the picker shows whatever tiers `coverCharge.tiers` returns).
- **Posts.** Share links to posts are the posts thread's work; its canvas (https://claude.ai/artifact/9BFP8Jd79xP4JZa3r9C1S8) has an App Clip row on these tokens. `ClipLink` still accepts venues, events, people and pings only; a post link shows the unsupported screen until that lands.
- **Figtree** is not bundled in the clip (size); it uses the system font with the same scale and weights.

## Open for Rick

- [x] Tipping stays in the clip (Rick, 2026-10-23, comment on the mockups).
- [ ] Agree the clip drops RSVP and Ping join (they stay the app's reasons to install). The merged build has them.
- [ ] "Pay it forward" tier: real, or cut from the picker.
- [ ] Add to Wallet on the pass: phase 1 or later (it needs a pass type id and a signing certificate).
- [ ] Keep the 15 MB budget (recommended) and swap the payment SDKs before the first archive.
