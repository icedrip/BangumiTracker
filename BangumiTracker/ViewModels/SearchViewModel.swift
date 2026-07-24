import Foundation
import Observation

enum SearchTab: String, CaseIterable, Sendable {
    case subject = "条目"
    case character = "角色"
    case person = "人物"
}

@MainActor
@Observable
final class SearchViewModel {
    var searchQuery: String = ""
    var searchResults: [Subject] = []
    var characterResults: [CharacterSearchResult] = []
    var personResults: [PersonSearchResult] = []
    var searchHistory: [SearchHistory] = []
    var selectedSearchTab: SearchTab = .subject
    var isSearching = false
    var errorMessage: String?
    /// Subject IDs the user has collected, best-effort seeded from the SwiftData
    /// cache. Drives the "已收藏" marker on subject search results; a subject
    /// collected but not yet in cache simply won't show the marker (the detail
    /// page still reflects the real status). Updated on every add from search.
    var collectedSubjectIds: Set<Int> = []

    private let api: BangumiAPIClient
    private let cache: LocalCacheService
    private var searchTask: Task<Void, Never>?
    /// Monotonic token bumped at the start of every `search()` invocation. A
    /// search that's superseded by a newer one (tab switch / new keystroke /
    /// history pick) bails before writing results, so a slow in-flight request
    /// can't overwrite the fresher results the user already sees.
    private var searchToken = 0

    init(api: BangumiAPIClient, cache: LocalCacheService) {
        self.api = api
        self.cache = cache
        self.collectedSubjectIds = Set(cache.getCachedCollections().map { $0.subjectId })
    }

    func search() async {
        searchToken &+= 1
        let token = searchToken
        let keyword = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else {
            searchResults = []
            characterResults = []
            personResults = []
            // Clear a stale error when the box is emptied — otherwise the last
            // failed search's message lingers over an empty input.
            errorMessage = nil
            return
        }
        isSearching = true
        errorMessage = nil
        defer {
            // Only stand down the indicator if no newer search has superseded
            // this one — a stale task rolling back through defer would otherwise
            // prematurely clear the active search's spinner.
            if token == searchToken { isSearching = false }
        }

        do {
            switch selectedSearchTab {
            case .subject:
                let r = try await api.searchSubjects(keyword: keyword)
                guard token == searchToken else { return }
                searchResults = r
            case .character:
                let r = try await api.searchCharacters(keyword: keyword)
                guard token == searchToken else { return }
                characterResults = r
            case .person:
                let r = try await api.searchPersons(keyword: keyword)
                guard token == searchToken else { return }
                personResults = r
            }
            guard token == searchToken else { return }
            cache.addSearchHistory(keyword: keyword, searchType: selectedSearchTab.rawValue)
            loadHistory()
        } catch {
            guard token == searchToken else { return }
            errorMessage = error.localizedDescription
        }
    }

    func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            // 200ms debounce per PRD 5.2.8 — fires only after input settles.
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self?.search()
        }
    }

    /// Cancels any pending debounced search and runs one immediately. Used by
    /// deliberate actions (tab switch / history pick / submit / retry) that
    /// shouldn't wait for the debounce. Routing these through the same
    /// `searchTask` plus the `searchToken` guard guarantees only one search's
    /// results land — a bare `Task { await search() }` would race a pending
    /// debounce task and could let the older one overwrite the newer.
    func searchImmediately() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.search()
        }
    }

    func clearResults() {
        searchResults = []
        characterResults = []
        personResults = []
    }

    func loadHistory() {
        // History is stored per search-type; only show entries for the active tab.
        searchHistory = cache.getSearchHistory(searchType: selectedSearchTab.rawValue)
    }

    func clearHistory() {
        cache.clearSearchHistory()
        searchHistory = []
    }

    func isCollected(_ subjectId: Int) -> Bool {
        collectedSubjectIds.contains(subjectId)
    }

    /// Re-seeds `collectedSubjectIds` from the SwiftData cache. The cache is the
    /// source of truth and is updated by other tabs' mutations (Home / Explore /
    /// Watching); without this, the mirror set at init goes stale and the
    /// "已收藏" marker is absent for items the user collected elsewhere.
    func refreshCollectedSubjectIds() {
        collectedSubjectIds = Set(cache.getCachedCollections().map { $0.subjectId })
    }

    /// Quick-add straight to 想看 (the `[+想看]` affordance on subject cards
    /// across Home/Explore/Watching/Search — no panel, per PRD 5.2.11).
    func addToWishlist(_ subject: Subject) async {
        do {
            var payload = UserSubjectCollectionModifyPayload()
            payload.type = CollectionType.wish.rawValue
            try await api.updateCollection(subjectId: subject.id, payload: payload)
            collectedSubjectIds.insert(subject.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Full add from the AddToCollectionSheet (status/tags/comment/private).
    /// Returns nil on success or an error string for the sheet to surface.
    func addCollection(subject: Subject, payload: UserSubjectCollectionModifyPayload) async -> String? {
        do {
            try await api.updateCollection(subjectId: subject.id, payload: payload)
            collectedSubjectIds.insert(subject.id)
            errorMessage = nil
            return nil
        } catch {
            let msg = error.localizedDescription
            errorMessage = msg
            return msg
        }
    }

    /// Fetches a subject by raw ID/URL for the manual-add flow. Throws on
    /// failure (invalid id / 404 / network) so the caller can surface the error
    /// locally — the generic `errorMessage` is only shown in the results area
    /// when there are no results, so a bad-ID 404 would otherwise be invisible.
    func fetchSubjectForAdd(id: Int) async throws -> Subject {
        try await api.fetchSubject(id: id)
    }
}
