import Foundation

let id = "22b6d3ff-0140-4f46-b814-e8dc4c10a476"
func link(_ text: String) -> ClipLink? { URL(string: text).flatMap(ClipLink.init(url:)) }
let valid = link("https://hotmess.social/events/\(id)?e=123.signature")!
assert(valid.path == "/events/\(id)")
assert(valid.expiry == "123.signature")
assert(valid.websiteURL.absoluteString.contains("e=123.signature"))
let request = valid.requestURL(apiBase: URL(string: "https://api.next.audiencekit.com")!, audienceHost: "hotmess.admin.next.audiencekit.com")
let query = URLComponents(url: request, resolvingAgainstBaseURL: false)!.queryItems!
assert(request.host == "api.next.audiencekit.com")
assert(query.contains(URLQueryItem(name: "host", value: "hotmess.admin.next.audiencekit.com")))
assert(query.contains(URLQueryItem(name: "e", value: "123.signature")))
assert(link("https://www.hotmess.social/venues/\(id.uppercased())/")?.path == "/venues/\(id)")
assert(link("https://hotmess.social/events/\(id)?e=")?.expiry == "")
for invalid in [
    "http://hotmess.social/events/\(id)",
    "https://hotmess.social.evil.example/events/\(id)",
    "https://user@hotmess.social/events/\(id)",
    "https://hotmess.social:444/events/\(id)",
    "https://hotmess.social/venues/\(id)/chat",
    "https://hotmess.social/events/not-a-uuid",
    "https://hotmess.social/events/\(id)?e=a&e=b"
] { assert(link(invalid) == nil, invalid) }
let fixture = Data(#"{"title":"Tonight","description":"At the venue","image":null}"#.utf8)
let decoded = try JSONDecoder().decode(ClipCard.self, from: fixture)
assert(decoded.title == "Tonight")
print("App Clip link and public-card checks passed")

assert(link("https://hotmess.social/people/\(id)")?.kind == "people")
assert(link("https://hotmess.social/pings/\(id)?e=v2.opaque")?.expiry == "v2.opaque")

// Tip amounts: chips inside the performer's bounds, the suggested chip, typed amounts.
let amounts = ClipTipAmounts(presetCents: [500, 1000, 1000, 2000, 5000, 100], minimumCents: 200, maximumCents: 2500, currency: "usd")
assert(amounts.chips == [500, 1000, 2000])
assert(amounts.suggested == 1000)
assert(amounts.cents(fromTyped: "7") == 700)
assert(amounts.cents(fromTyped: "7.50") == 750)
assert(amounts.cents(fromTyped: "7,50") == 750)
assert(amounts.cents(fromTyped: "1") == nil, "below the minimum")
assert(amounts.cents(fromTyped: "26") == nil, "above the maximum")
assert(amounts.cents(fromTyped: "") == nil)
assert(amounts.cents(fromTyped: "abc") == nil)
assert(amounts.boundsText == "$2 to $25")
let open = ClipTipAmounts(presetCents: [300], minimumCents: 100, maximumCents: 0, currency: "usd")
assert(open.suggested == 300)
assert(open.isAllowed(100_000))
assert(open.boundsText == "$1 or more")
assert(ClipTipAmounts.whole(1050, "usd") == "$10.50")
print("App Clip tip amount checks passed")

// The share card's `clip` block (GET /v1/share?view=clip), as audience_kit_api doc/APP_CLIP_CHECKOUT.md answers it.
let venueID = "6f1c1d2e-0000-4000-8000-000000000001"
let coverCard = Data("""
{"title":"Purr","description":"","image":null,"clip":{"kind":"cover","venue_id":"\(venueID)","sign_in_required":false,
"cover":{"night":"2026-10-09","event_id":null,"amount_cents":1000,"fee_cents":50,"total_cents":1112,"currency":"usd",
"cover_from":"21:00","cover_until":null,"tiers":[{"id":"vip","name":"VIP","description":"Skip the line","amount_cents":2000,"total_cents":2212,"currency":"usd"}],
"payable":true,"provider":"stripe","guest_checkout":true,"max_quantity":10}}}
""".utf8)
let coverOffer = try ClipOffer.decoder().decode(ClipCard.self, from: coverCard).clip!
assert(coverOffer.guestCover?.venueID == UUID(uuidString: venueID))
assert(coverOffer.cover?.totalCents == 1112 && coverOffer.cover?.tiers.first?.feeCents == nil)
assert(coverOffer.guestTipping == nil)
let square = try ClipOffer.decoder().decode(ClipOffer.self, from: Data("""
{"kind":"cover","venue_id":"\(venueID)","sign_in_required":false,"cover":{"night":"2026-10-09","amount_cents":1000,
"total_cents":1000,"currency":"usd","tiers":[],"payable":true,"provider":"square","guest_checkout":false}}
""".utf8))
assert(square.guestCover == nil, "Square goes to the app")
let community = try ClipOffer.decoder().decode(ClipOffer.self, from: Data(#"{"kind":"cover","venue_id":null,"cover":null,"sign_in_required":true}"#.utf8))
assert(community.signInRequired && community.guestCover == nil)
let tipOffer = try ClipOffer.decoder().decode(ClipOffer.self, from: Data("""
{"kind":"tip","person_id":"\(venueID)","sign_in_required":false,"tipping":{"in_app":true,"provider":"stripe",
"guest_checkout":true,"minimum_cents":100,"maximum_cents":20000,"preset_cents":[500,1000,2000],"fee_payer":"fan",
"note_length":140,"quotes":[{"amount_cents":1000,"fee_cents":61,"total_cents":1061,"currency":"usd"}]}}
""".utf8))
assert(tipOffer.guestTipping?.tipping.quote(for: 1000)?.totalCents == 1061)
assert(tipOffer.guestTipping?.tipping.amounts.suggested == 1000)
// A card without `clip` (pings, older APIs) still decodes.
let plain = try ClipOffer.decoder().decode(ClipCard.self, from: fixture)
assert(plain.clip == nil)
print("App Clip guest offer checks passed")

// Claim tokens: kept per host, claimed ones dropped, ALREADY_HAS_COVER kept as a guest pass for the night.
var list = GuestPurchaseList()
list.add(GuestPurchase(kind: .cover, id: "a1", claimToken: "t1", host: "hotmess.social", venueID: venueID.uppercased(), night: "2026-10-09"))
list.add(GuestPurchase(kind: .tip, id: "p1", claimToken: "t2", host: "hotmess.social"))
list.add(GuestPurchase(kind: .cover, id: "a2", claimToken: "t3", host: "next.example", venueID: venueID, night: "2026-10-09"))
assert(list.claimable(host: "hotmess.social") == ["t1", "t2"])
assert(list.cover(venueID: venueID, night: "2026-10-09")?.id == "a2")
list.apply(claimed: ["t2"], notFound: [], alreadyHasCover: ["t1"])
assert(list.claimable(host: "hotmess.social").isEmpty, "a kept guest pass isn't retried")
assert(list.purchase(id: "a1")?.keptAsGuest == true && list.purchase(id: "p1") == nil)
list.prune(now: .now, today: "2026-10-10")
assert(list.purchase(id: "a1") == nil, "a kept guest pass goes once its night is over")
assert(list.purchase(id: "a2") != nil)
list.remove(token: "t3")
assert(list.purchases.isEmpty)
var old = GuestPurchaseList()
old.add(GuestPurchase(kind: .tip, id: "p2", claimToken: "t4", createdAt: .now.addingTimeInterval(-GuestPurchaseList.lifetime - 1)))
old.prune(today: "2026-10-10")
assert(old.purchases.isEmpty)
let early = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 3))!
assert(GuestPurchaseList.today(now: early, calendar: Calendar(identifier: .gregorian)) == "2026-10-09", "before 6am it's still last night")
print("App Clip guest purchase checks passed")
