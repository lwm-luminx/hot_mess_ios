import Foundation

/// Only public venue/event links are valid Clip invocations. Preserve signed expiry.
struct ClipLink: Equatable, Sendable {
    let path: String
    let expiry: String?

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              ["hotmess.social", "www.hotmess.social"].contains(parts.host?.lowercased() ?? "")
        else { return nil }
        let segments = parts.path.split(separator: "/")
        guard segments.count == 2, ["venues", "events", "people", "pings"].contains(String(segments[0])),
              let id = UUID(uuidString: String(segments[1])) else { return nil }
        let expiries = (parts.queryItems ?? []).filter { $0.name == "e" }
        guard expiries.count <= 1 else { return nil }
        path = "/\(segments[0])/\(id.uuidString.lowercased())"
        expiry = expiries.first.map { $0.value ?? "" }
    }

    var kind: String { String(path.split(separator: "/")[0]) }
    var id: String { String(path.split(separator: "/")[1]) }

    func requestURL(apiBase: URL, audienceHost: String) -> URL {
        var parts = URLComponents(url: apiBase.appendingPathComponent("v1/share"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "host", value: audienceHost), URLQueryItem(name: "path", value: path)]
        if let expiry { parts.queryItems?.append(URLQueryItem(name: "e", value: expiry)) }
        return parts.url!
    }

    var websiteURL: URL {
        var parts = URLComponents(string: "https://hotmess.social\(path)")!
        if let expiry { parts.queryItems = [URLQueryItem(name: "e", value: expiry)] }
        return parts.url!
    }
}

struct ClipCard: Decodable, Sendable {
    struct Image: Decodable, Sendable {
        let url: URL
        let alt: String
    }
    let title: String
    let description: String
    let image: Image?
}
