//
//  SupportScreen.swift
//  HotMess
//

import CoreLocation
import SwiftUI

/// "Need support?": free, confidential crisis and support lines for where the
/// user is, from the API's support config (`supportResources`), with Call and
/// Text and the number written out. 911 comes last. Reachable from Me and
/// from Get help, never gated on being at a venue. When staff shared it from
/// an alert, their note comes first.
struct SupportScreen: View {
    /// What staff wrote when they shared this from an alert.
    var sharedNote: String?

    @Environment(AppModel.self) private var model
    @State private var resources: SupportResources?
    @State private var failed = false

    var body: some View {
        List {
            if let sharedNote, !sharedNote.isEmpty {
                Section {
                    Text(sharedNote)
                        .font(.hotMess(.body))
                } header: {
                    Text("A note from the venue")
                }
            }

            Section {
                Text("You don't have to be in crisis to reach out. The people who answer are there to listen.")
                    .font(.hotMess(.body))
            }

            if let resources {
                Section {
                    ForEach(resources.lines) { line in
                        SupportLineRow(line: line, isFirst: line.id == resources.lines.first?.id)
                    }
                } header: {
                    Text("Talk to someone, any time")
                } footer: {
                    if let checked = resources.checkedDate {
                        Text("Numbers for \(resources.name), last checked \(checked.formatted(date: .abbreviated, time: .omitted)).")
                    } else {
                        Text("Numbers for \(resources.name).")
                    }
                }
                EmergencySection(number: resources.emergency)
            } else if failed {
                Section {
                    Text("Couldn't load support lines. In the US, call or text 988 any time.")
                        .font(.hotMess(.body))
                }
                EmergencySection()
            } else {
                Section { ProgressView() }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "Need support?"))
        .task { await load() }
    }

    private func load() async {
        let region = await Self.region(near: model.location.coordinates)
        do {
            resources = try await model.api.supportResources(region: region)
        } catch {
            failed = true
        }
    }

    /// Where the user is as ISO 3166-2 (US-UT) when the phone can tell from
    /// their last position, else their country from the device's region.
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
