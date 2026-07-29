import Foundation
import Observation

@MainActor
@Observable
final class SubjectDetailViewModel {
    var subject: Subject?
    var episodes: [Episode] = []
    var collection: UserSubjectCollection?
    var episodeCollections: [UserEpisodeCollection] = []
    var selectedStatus: CollectionType? = nil
    var userRating: Int = 0
    var userComment: String = ""
    var isLoading = false
    /// Load-path errors (subject/episodes/collection fetch failures). Shown as a
    /// full-screen retry empty state by the view when the subject couldn't load.
    var errorMessage: String?
    /// Action-path errors (rate / comment / tag / episode-mark / status change).
    /// Shown as a transient toast by the view. Kept separate from
    /// `errorMessage` so an action failure on an already-loaded page doesn't
    /// either (a) get swallowed (the retry empty state only renders when
    /// subject == nil) or (b) clobber a load error's retry UI.
    var actionError: String?

    private let api: BangumiAPIClient
    private let cache: LocalCacheService
    private var subjectId: Int?

    init(api: BangumiAPIClient, cache: LocalCacheService) {
        self.api = api
        self.cache = cache
    }

    func loadSubject(id: Int) async {
        self.subjectId = id
        isLoading = true
        errorMessage = nil

        // Clear previous user-specific state so we always reflect the latest server state.
        collection = nil
        episodeCollections = []
        selectedStatus = nil
        userRating = 0
        userComment = ""
        // Also drop the extra-data rails so a re-load on the same VM (e.g. an
        // auth-state flip via `.task(id:)`) doesn't show the prior subject's
        // characters / persons / related subjects until the new fetch lands.
        characters = []
        persons = []
        relatedSubjects = []

        // Seed from cache for instant first paint
        if let cached = cache.getCachedSubject(id: id) {
            self.subject = Subject(from: cached)
        }

        async let subjectRequest = api.fetchSubject(id: id)
        async let episodesRequest = api.fetchEpisodes(subjectId: id)

        do {
            self.subject = try await subjectRequest
            if let s = self.subject {
                try cache.cacheSubjects([s])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            self.episodes = try await episodesRequest
            let mainCount = episodes.filter { $0.type == .main }.count
            cache.updateCachedSubjectEpisodeCount(id: id, count: mainCount)
        } catch {
            // non-fatal — keep subject content
        }

        await loadCollection()
        await loadEpisodeCollections()
        await loadExtraData()

        isLoading = false
    }

    func loadEpisodes() async {
        guard let id = subjectId else { return }
        do {
            episodes = try await api.fetchEpisodes(subjectId: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadCollection() async {
        guard let id = subjectId else { return }
        do {
            let c = try await api.fetchUserCollection(subjectId: id)
            self.collection = c
            self.selectedStatus = c.collectionType
            self.userRating = c.rate
            self.userComment = c.comment ?? ""
        } catch BangumiAPIError.httpError(404) {
            self.collection = nil
            self.selectedStatus = nil
            self.userRating = 0
            self.userComment = ""
        } catch BangumiAPIError.unauthorized {
            self.collection = nil
            self.selectedStatus = nil
            self.userRating = 0
            self.userComment = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadEpisodeCollections() async {
        guard let id = subjectId else { return }
        do {
            episodeCollections = try await api.fetchEpisodeCollection(subjectId: id)
        } catch BangumiAPIError.httpError(404), BangumiAPIError.unauthorized {
            episodeCollections = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadExtraData() async {
        guard let id = subjectId else { return }
        async let chars = api.fetchSubjectCharacters(subjectId: id)
        async let prsns = api.fetchSubjectPersons(subjectId: id)
        async let related = api.fetchRelatedSubjects(subjectId: id)
        do { characters = try await chars } catch { /* non-fatal */ }
        do { persons = try await prsns } catch { /* non-fatal */ }
        do { relatedSubjects = try await related } catch { /* non-fatal */ }
    }

    func updateStatus(_ type: CollectionType) async {
        guard let id = subjectId else { return }
        let previous = selectedStatus
        selectedStatus = type
        do {
            var payload = UserSubjectCollectionModifyPayload()
            payload.type = type.rawValue
            try await api.updateCollection(subjectId: id, payload: payload)
            // Sync the per-user "added to wish" stamp used by the Home wish-list
            // sort. Only acts on transitions in/out of .wish — same-status retaps
            // are a no-op so we don't reset the timestamp on the user.
            if previous != type, let userId = try? await api.resolveUserId() {
                if type == .wish {
                    cache.recordWishCollectedAt(userId: userId, subjectId: id)
                } else if previous == .wish {
                    cache.clearWishCollectedAt(userId: userId, subjectId: id)
                }
            }
            await loadCollection()
        } catch {
            selectedStatus = previous
            actionError = error.localizedDescription
        }
    }

    func markEpisodeWatched(episodeId: Int) async {
        guard let id = subjectId else { return }
        let isAlreadyWatched = episodeCollections.first(where: { $0.episode.id == episodeId })?.type == .watched
        let newType: EpisodeCollectionType = isAlreadyWatched ? .none : .watched
        let snapshot = episodeCollections
        episodeCollections = episodeCollections.map { uec in
            uec.episode.id == episodeId
                ? UserEpisodeCollection(episode: uec.episode, type: newType, updatedAt: uec.updatedAt)
                : uec
        }
        do {
            try await api.updateEpisodeCollection(subjectId: id, episodeId: episodeId, type: newType)
            // Optimistic state already reflects the server-confirmed outcome;
            // `updateEpisodeCollection` invalidated the cache, so the next visit
            // refetches fresh. Skipping the reload keeps every tap <200ms (PRD 7.1).
        } catch {
            episodeCollections = snapshot
            actionError = error.localizedDescription
        }
    }

    func markNextEpisodeWatched() async {
        guard let id = subjectId else { return }
        let watched = watchedEpisodeIds
        let mainSorted = episodes.filter { $0.type == .main }.sorted { $0.sort < $1.sort }
        guard let next = mainSorted.first(where: { !watched.contains($0.id) }) else { return }
        let snapshot = episodeCollections
        episodeCollections = episodeCollections.map { uec in
            uec.episode.id == next.id
                ? UserEpisodeCollection(episode: uec.episode, type: .watched, updatedAt: uec.updatedAt)
                : uec
        }
        do {
            try await api.updateEpisodeCollection(subjectId: id, episodeId: next.id, type: .watched)
        } catch {
            episodeCollections = snapshot
            actionError = error.localizedDescription
        }
    }

    func markAllWatched() async {
        guard let id = subjectId else { return }
        let mainEps = episodes.filter { $0.type == .main }
        guard !mainEps.isEmpty else { return }
        let mainIds = Set(mainEps.map(\.id))
        let snapshot = episodeCollections
        episodeCollections = episodeCollections.map { uec in
            mainIds.contains(uec.episode.id)
                ? UserEpisodeCollection(episode: uec.episode, type: .watched, updatedAt: uec.updatedAt)
                : uec
        }
        do {
            try await api.batchUpdateEpisodeCollections(
                subjectId: id,
                episodes: mainEps.map { ($0.id, EpisodeCollectionType.watched) }
            )
        } catch {
            episodeCollections = snapshot
            actionError = error.localizedDescription
        }
    }

    func unmarkAll() async {
        guard let id = subjectId else { return }
        let mainEps = episodes.filter { $0.type == .main }
        guard !mainEps.isEmpty else { return }
        let mainIds = Set(mainEps.map(\.id))
        let snapshot = episodeCollections
        episodeCollections = episodeCollections.map { uec in
            mainIds.contains(uec.episode.id)
                ? UserEpisodeCollection(episode: uec.episode, type: .none, updatedAt: uec.updatedAt)
                : uec
        }
        do {
            try await api.batchUpdateEpisodeCollections(
                subjectId: id,
                episodes: mainEps.map { ($0.id, EpisodeCollectionType.none) }
            )
        } catch {
            episodeCollections = snapshot
            actionError = error.localizedDescription
        }
    }

    // MARK: - Book progress (ep_status / vol_status)

    /// Books track progress as integer `ep_status` / `vol_status` on the
    /// collection itself — NOT per-episode (the episode-collection endpoints
    /// 404 for books). Anime/real go through the episode-collection methods
    /// above; this is the book-only path.
    enum BookProgressField { case ep, vol }

    func adjustBookProgress(_ field: BookProgressField, by delta: Int) async {
        guard let id = subjectId, var c = collection else { return }
        // Optimistic: mutate the displayed value BEFORE the await so the stepper
        // is responsive AND rapid taps accumulate (each tap reads the live,
        // already-incremented value rather than a stale pre-network snapshot).
        // Matches `rate(_:)`; rolls back on failure.
        let previous: Int
        switch field {
        case .ep:
            previous = c.epStatus
            c.epStatus = max(0, c.epStatus + delta)
        case .vol:
            previous = c.volStatus
            c.volStatus = max(0, c.volStatus + delta)
        }
        self.collection = c
        var payload = UserSubjectCollectionModifyPayload()
        switch field {
        case .ep: payload.epStatus = c.epStatus
        case .vol: payload.volStatus = c.volStatus
        }
        do {
            try await api.updateCollection(subjectId: id, payload: payload)
        } catch {
            if var rolled = self.collection {
                switch field {
                case .ep: rolled.epStatus = previous
                case .vol: rolled.volStatus = previous
                }
                self.collection = rolled
            }
            actionError = error.localizedDescription
        }
    }

    func rate(_ score: Int) async {
        guard let id = subjectId else { return }
        let previous = userRating
        userRating = score
        do {
            var payload = UserSubjectCollectionModifyPayload()
            payload.rate = score
            try await api.updateCollection(subjectId: id, payload: payload)
        } catch {
            // Roll back so the stars don't linger on a value the server rejected
            // — matches `adjustBookProgress`. The error surfaces via the toast.
            userRating = previous
            actionError = error.localizedDescription
        }
    }

    func updateComment(_ comment: String) async {
        guard let id = subjectId else { return }
        let previous = userComment
        userComment = comment
        do {
            var payload = UserSubjectCollectionModifyPayload()
            payload.comment = comment
            try await api.updateCollection(subjectId: id, payload: payload)
            // Skip the reload: `userComment` already holds the new value (and the
            // ReviewSection bubble reads from it), so a refetch would only risk
            // transiently overwriting the optimistic value with a lagging server
            // snapshot. `updateCollection` invalidated the cache for next visit.
        } catch {
            userComment = previous
            actionError = error.localizedDescription
        }
    }

    func addTag(_ tag: String) async {
        guard let id = subjectId else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var newTags = collection?.tags ?? []
        guard !newTags.contains(trimmed) else { return }
        newTags.append(trimmed)
        do {
            var payload = UserSubjectCollectionModifyPayload()
            payload.tags = newTags
            try await api.updateCollection(subjectId: id, payload: payload)
            await loadCollection()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Computed

    var watchedEpisodeCount: Int {
        episodeCollections.filter { $0.type == .watched && $0.episode.type == .main }.count
    }

    var totalEpisodes: Int {
        let mainCount = episodes.filter { $0.type == .main }.count
        if mainCount > 0 { return mainCount }
        return subject?.totalEpisodes ?? 0
    }

    /// Books use ep_status/vol_status, not episode collections — gates the
    /// book-specific progress UI vs the per-episode grid.
    var isBook: Bool { subject?.type == SubjectType.book.rawValue }

    /// Music subjects use disc-based grouping instead of the flat episode grid.
    var isMusic: Bool { subject?.type == SubjectType.music.rawValue }

    /// Games only need collection status + rating — no per-episode tracking.
    var isGame: Bool { subject?.type == SubjectType.game.rawValue }

    /// The subject type for status-label verb selection (看/读/听/玩).
    var subjectType: SubjectType? {
        guard let type = subject?.type else { return nil }
        return SubjectType(rawValue: type)
    }

    var watchedEpisodeIds: Set<Int> {
        Set(episodeCollections.filter { $0.type == .watched }.map(\.episode.id))
    }

    var hasCharacterData: Bool { !characters.isEmpty }
    var hasPersonData: Bool { !persons.isEmpty }
    var hasRelatedData: Bool { !relatedSubjects.isEmpty }

    var characters: [SubjectCharacter] = []
    var persons: [SubjectPerson] = []
    var relatedSubjects: [RelatedSubject] = []
}
