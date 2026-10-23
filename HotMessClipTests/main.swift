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
