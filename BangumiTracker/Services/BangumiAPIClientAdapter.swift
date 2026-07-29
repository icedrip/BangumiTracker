import Foundation
import Kingfisher

/// Concrete adapter that forwards `BangumiAPIProtocol` calls to the
/// `BangumiAPIClient` actor. Required because Swift 6's strict concurrency
/// does not allow an actor to directly conform to a protocol with async
/// requirements — the adapter bridges the gap.
///
/// Usage: `BangumiAPIClientAdapter(api)` where `BangumiAPIProtocol` is expected.
/// ViewModels can accept `BangumiAPIProtocol` in their inits and receive
/// either this adapter (production) or a mock (testing).
final class BangumiAPIClientAdapter: BangumiAPIProtocol, @unchecked Sendable {
    private let actor: BangumiAPIClient
    init(_ actor: BangumiAPIClient) { self.actor = actor }

    func fetchCalendar() async throws -> [CalendarDay] { try await actor.fetchCalendar() }
    func fetchMe() async throws -> UserInfo { try await actor.fetchMe() }
    func searchSubjects(keyword: String, filter: SubjectSearchFilter?, sort: String?) async throws -> [Subject] {
        try await actor.searchSubjects(keyword: keyword, filter: filter, sort: sort)
    }
    func fetchUserCollections(username: String, type: Int?) async throws -> [UserSubjectCollection] {
        try await actor.fetchUserCollections(username: username, type: type)
    }
    func fetchUserCollectionsCount(username: String, type: Int) async throws -> Int {
        try await actor.fetchUserCollectionsCount(username: username, type: type)
    }
    func fetchEpisodeCollection(subjectId: Int) async throws -> [UserEpisodeCollection] {
        try await actor.fetchEpisodeCollection(subjectId: subjectId)
    }
    func updateCollection(subjectId: Int, payload: UserSubjectCollectionModifyPayload) async throws {
        try await actor.updateCollection(subjectId: subjectId, payload: payload)
    }
    func deleteCollection(subjectId: Int) async throws { try await actor.deleteCollection(subjectId: subjectId) }
    func fetchSubject(id: Int) async throws -> Subject { try await actor.fetchSubject(id: id) }
    func fetchEpisodes(subjectId: Int) async throws -> [Episode] { try await actor.fetchEpisodes(subjectId: subjectId) }
    func updateEpisodeCollection(subjectId: Int, episodeId: Int, type: EpisodeCollectionType) async throws {
        try await actor.updateEpisodeCollection(subjectId: subjectId, episodeId: episodeId, type: type)
    }
    func setToken(_ token: String?) async { await actor.setToken(token) }
    func currentGeneration() async -> Int { await actor.currentGeneration() }
    func hasToken() async -> Bool { await actor.hasToken() }
    func resolveUserId() async throws -> Int { try await actor.resolveUserId() }
    func fetchSubjectCharacters(subjectId: Int) async throws -> [SubjectCharacter] {
        try await actor.fetchSubjectCharacters(subjectId: subjectId)
    }
    func fetchSubjectPersons(subjectId: Int) async throws -> [SubjectPerson] {
        try await actor.fetchSubjectPersons(subjectId: subjectId)
    }
    func fetchCharacterDetail(id: Int) async throws -> CharacterDetail { try await actor.fetchCharacterDetail(id: id) }
    func fetchPersonDetail(id: Int) async throws -> PersonDetail { try await actor.fetchPersonDetail(id: id) }
    func searchCharacters(keyword: String) async throws -> [CharacterSearchResult] {
        try await actor.searchCharacters(keyword: keyword)
    }
    func searchPersons(keyword: String) async throws -> [PersonSearchResult] {
        try await actor.searchPersons(keyword: keyword)
    }
    func fetchSubjects(type: Int?, year: Int?, month: Int?, sort: String?) async throws -> [Subject] {
        try await actor.fetchSubjects(type: type, year: year, month: month, sort: sort)
    }
}
