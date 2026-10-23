import AudienceKit
import Foundation
import Testing
@testable import HotMess

struct AuthenticationHandoffTests {
    private func credential(_ token: String) -> Credential {
        Credential(token: token, userId: UUID().uuidString, audienceId: UUID().uuidString,
                   role: "member", endpoint: URL(string: "https://api.audiencekit.com/v1/audience/test/graphql")!)
    }

    @Test func clipLoginReplacesAnOlderMainLoginOnce() throws {
        let old = credential("old")
        let incoming = credential("incoming")
        let primary = InMemoryCredentialStore(credential: old)
        let clip = InMemoryCredentialStore(credential: incoming)
        let handoff = ClipCredentialHandoff(primary: primary, clip: clip)
        #expect(try handoff.load() == incoming)
        #expect(try primary.load() == incoming)
        #expect(try clip.load() == nil)
        #expect(try handoff.load() == incoming)
    }

    @Test func signOutCannotResurrectTheClipLogin() throws {
        let primary = InMemoryCredentialStore(credential: credential("main"))
        let clip = InMemoryCredentialStore(credential: credential("clip"))
        let handoff = ClipCredentialHandoff(primary: primary, clip: clip)
        try handoff.delete()
        #expect(try primary.load() == nil)
        #expect(try clip.load() == nil)
        #expect(try handoff.load() == nil)
    }

    @Test func newMainLoginSupersedesTheHandoff() throws {
        let primary = InMemoryCredentialStore()
        let clip = InMemoryCredentialStore(credential: credential("clip"))
        let handoff = ClipCredentialHandoff(primary: primary, clip: clip)
        let incoming = credential("main")
        try handoff.save(incoming)
        #expect(try handoff.load() == incoming)
        #expect(try clip.load() == nil)
    }
}
