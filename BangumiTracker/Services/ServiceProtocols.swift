import Foundation

// MARK: - Service Protocols

/// Protocol for the Bangumi API client. Each method mirrors a `BangumiAPIClient`
/// method signature. Methods that cross actor boundaries are declared `async`.
protocol BangumiAPIProtocol: AnyObject, Sendable {
    func fetchCalendar() async throws -> [CalendarDay]
    func fetchMe() async throws -> UserInfo
    func searchSubjects(keyword: String, filter: SubjectSearchFilter?, sort: String?) async throws -> [Subject]
    func fetchUserCollections(username: String, type: Int?) async throws -> [UserSubjectCollection]
    func fetchUserCollectionsCount(username: String, type: Int) async throws -> Int
    func fetchEpisodeCollection(subjectId: Int) async throws -> [UserEpisodeCollection]
    func updateCollection(subjectId: Int, payload: UserSubjectCollectionModifyPayload) async throws
    func deleteCollection(subjectId: Int) async throws
    func fetchSubject(id: Int) async throws -> Subject
    func fetchEpisodes(subjectId: Int) async throws -> [Episode]
    func updateEpisodeCollection(subjectId: Int, episodeId: Int, type: EpisodeCollectionType) async throws
    func setToken(_ token: String?) async
    func currentGeneration() async -> Int
    func hasToken() async -> Bool
    func resolveUserId() async throws -> Int
    func fetchSubjectCharacters(subjectId: Int) async throws -> [SubjectCharacter]
    func fetchSubjectPersons(subjectId: Int) async throws -> [SubjectPerson]
    func fetchCharacterDetail(id: Int) async throws -> CharacterDetail
    func fetchPersonDetail(id: Int) async throws -> PersonDetail
    func searchCharacters(keyword: String) async throws -> [CharacterSearchResult]
    func searchPersons(keyword: String) async throws -> [PersonSearchResult]
    func fetchSubjects(type: Int?, year: Int?, month: Int?, sort: String?) async throws -> [Subject]
}

/// Protocol for local SwiftData cache.
protocol LocalCacheProtocol: AnyObject, Sendable {
    func getCachedSubject(id: Int) -> CachedSubject?
    func getCachedCollections(type: CollectionType?) -> [CachedUserCollection]
    func getCachedCollection(subjectId: Int) -> CachedUserCollection?
    func cachedCollectionCount() -> Int
    var lastCollectionCacheAt: Date? { get set }
    func cacheSubjects(_ subjects: [Subject]) throws
    func cacheCollections(_ collections: [UserSubjectCollection]) throws
    func upsertCachedCollectionType(subjectId: Int, type: CollectionType, subjectType: Int)
    func updateCachedSubjectEpisodeCount(id: Int, count: Int)
    func removeCachedCollection(subjectId: Int)
    func recordWishCollectedAt(userId: Int, subjectId: Int, at: Date)
    func clearWishCollectedAt(userId: Int, subjectId: Int)
    func wishCollectedAtMap(userId: Int, subjectIds: [Int]) -> [Int: Date]
}

// MARK: - Conformances

// To adopt the protocols in production, create an adapter that forwards calls
// to BangumiAPIClient (see BangumiAPIClientAdapter.swift pattern), then pass
// the adapter to ViewModels. Swift 6's strict concurrency prevents actors from
// conforming directly to protocols with async requirements.
//
// Once all ViewModels accept BangumiAPIProtocol / LocalCacheProtocol instead
// of concrete types, tests can inject mock implementations.
