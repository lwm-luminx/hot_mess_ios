//
//  SupportLines.swift
//  HotMess
//

import CoreLocation
import SwiftUI

/// Where the support lines and ride apps are for: ISO 3166-2 (US-UT) when the
/// phone can tell from the user's last position, else their country from the
/// device's region.
enum SupportRegion {
    static func region(near coordinates: Coordinates?) async -> String? {
        let country = Locale.current.region?.identifier
        guard let coordinates else { return country }
        let location = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
              let code = placemark.isoCountryCode
        else { return country }
        if let area = placemark.administrativeArea, area.count <= 3, area.allSatisfy(\.isLetter) {
            return "\(code)-\(area.uppercased())"
        }
        return code
    }
}

/// "Talk to someone, any time": the free, confidential crisis and support
/// lines for where the user is (`supportResources`), with Call and Text and
/// the number written out. Part of "Need support?", which also lists the
/// city's resources; these work in any city, or with none chosen.
struct SupportLinesSection: View {
    let resources: SupportResources

    var body: some View {
        Section {
            ForEach(resources.lines) { line in
                SupportLineRow(line: line, isFirst: line.id == resources.lines.first?.id)
            }
        } header: {
            Text("Talk to someone, any time")
        } footer: {
            if let checked = resources.checkedDate {
                Text("You don't have to be in crisis to reach out. Numbers for \(resources.name), last checked \(checked.formatted(date: .abbreviated, time: .omitted)).")
            } else {
                Text("You don't have to be in crisis to reach out. Numbers for \(resources.name).")
            }
        }
    }
}

/// A support line: its name, who it's for, the numbers written out, then
/// Call and Text. The first line's Call is the filled button.
struct SupportLineRow: View {
    let line: SupportResources.Line
    let isFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(line.name)
                .font(.hotMess(.body, weight: .bold))
            if let description = line.description {
                Text(description)
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
            }
            if !line.numbers.isEmpty {
                Text(line.numbers)
                    .font(.hotMess(.footnote))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if let call = line.callURL {
                    if isFirst {
                        Link(String(localized: "Call"), destination: call).buttonStyle(.borderedProminent)
                    } else {
                        Link(String(localized: "Call"), destination: call).buttonStyle(.bordered)
                    }
                }
                if let text = line.textURL {
                    Link(String(localized: "Text"), destination: text).buttonStyle(.bordered)
                }
                if line.callURL == nil, line.textURL == nil, let site = line.websiteURL {
                    Link(String(localized: "Website"), destination: site).buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
