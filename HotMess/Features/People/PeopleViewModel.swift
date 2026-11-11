//
//  PeopleViewModel.swift
//  HotMess
//

import AudienceKit
import Foundation
import Observation

extension Person {
    /// A list row's worth of person from AudienceKit GraphQL. The detail
    /// screen still loads the full person over REST by its UUID.
    init?(_ person: AudienceKit.Person, resolve: (String?) -> URL?) {
        guard let id = RecordID.uuid(person.id) else { return nil }
        // Optional in the SDK once people can be added without a Facebook Page;
        // binding it this way compiles against SDK versions before and after.
        let page: AudienceKit.Page? = person.page

        self.init(
            id: id,
            name: person.name,
            avatarURL: resolve(person.avatarUrl) ?? resolve(page?.photoUrl),
            bannerURL: resolve(person.bannerUrl) ?? resolve(page?.bannerUrl)
        )
    }
}

@MainActor
@Observable
final class PeopleViewModel {
    private(set) var state: LoadState<PeopleListing> = .idle

    private let audienceKit: AudienceKitClient

    init(audienceKit: AudienceKitClient) {
        self.audienceKit = audienceKit
    }

    /// The people the audience follows, with their home venues, gigs and the
    /// friends with them, from AudienceKit GraphQL.
    func load() async {
        if state.value == nil { state = .loading }

        do {
            let people = try await audienceKit.people()
            state = .loaded(PeopleListing(
                everyone: people
                    .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
                    .compactMap { PersonEntry($0, resolve: audienceKit.url(for:)) }
            ))
        } catch is CancellationError {
        } catch let error as AudienceKitError {
            state = LoadState(catching: APIError(error))
        } catch {
            state = LoadState(catching: error)
        }
    }
}

@MainActor
@Observable
final class PersonViewModel {
    private(set) var state: LoadState<PersonDetail> = .idle
    /// Their crowns and reigns (Miss Gay Utah, Empress of the Royal Court), reigning first. Empty
    /// until loaded, when they have none, or when the API can't say; never holds up the page.
    private(set) var titles: [PersonOffice] = []

    private let api: HotMessAPI
    private let audienceKit: AudienceKitClient
    private let personID: UUID

    init(api: HotMessAPI, audienceKit: AudienceKitClient, personID: UUID) {
        self.api = api
        self.audienceKit = audienceKit
        self.personID = personID
    }

    func load() async {
        if state.value == nil { state = .loading }

        async let titles = Self.titles(of: personID, from: audienceKit)
        do {
            state = .loaded(try await api.person(personID))
        } catch is CancellationError {
        } catch {
            state = LoadState(catching: error)
        }
        self.titles = await titles
    }

    /// Reigning before former, newest reign first within each.
    private static func titles(of personID: UUID, from audienceKit: AudienceKitClient) async -> [PersonOffice] {
        let titles = (try? await audienceKit.titles(personID: personID.uuidString.lowercased())) ?? []
        return titles.sorted {
            let reigning = ($0.status != .former, $0.termStart ?? "")
            let other = ($1.status != .former, $1.termStart ?? "")
            return reigning.0 != other.0 ? reigning.0 : reigning.1 > other.1
        }
    }
}
