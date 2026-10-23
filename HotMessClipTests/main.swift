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
