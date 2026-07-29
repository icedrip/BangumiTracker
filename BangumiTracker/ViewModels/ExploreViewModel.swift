import Foundation
import Observation

@MainActor
@Observable
final class ExploreViewModel {
    var rankings: [Subject] = []
    var popularSubjects: [Subject] = []
    var isLoading = false
    var errorMessage: String?
    var actionError: String?
    /// Subject ID → collection status, seeded from the SwiftData cache and kept
    /// in sync on adds. Lets carousel/grid cards do an in-memory lookup instead
    /// of a per-card SwiftData fetch (the BrowseView grid can surface dozens of
    /// subjects — N fetches per body re-evaluation otherwise).
    var collectionOverlay: [Int: CollectionType] = [:]

    let seasonOptions: [String]

    /// URLs of cover images currently visible, for prefetching.
    var visibleImageURLs: [String] {
        (rankings + popularSubjects).compactMap(\.imageURL)
    }

    private let api: BangumiAPIClient
    private let cache: LocalCacheService

    init(api: BangumiAPIClient, cache: LocalCacheService) {
        self.api = api
        self.cache = cache
        self.seasonOptions = ExploreViewModel.computeSeasonOptions()
        self.collectionOverlay = Self.buildCollectionOverlay(from: cache)
    }

    private static func buildCollectionOverlay(from cache: LocalCacheService) -> [Int: CollectionType] {
        Dictionary(
            cache.getCachedCollections().map { ($0.subjectId, CollectionType(rawValue: $0.collectionType) ?? .wish) },
            uniquingKeysWith: { a, _ in a }
        )
    }

    private static func computeSeasonOptions() -> [String] {
        // Anime seasons start in Jan / Apr / Jul / Oct. Lead with the next upcoming season,
        // then the current season and three past seasons.
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)

        let seasonMonths = [1, 4, 7, 10]
        var year = currentYear
        var month = seasonMonths.first(where: { $0 > currentMonth }) ?? 1
        if month == 1 && currentMonth >= 10 {
            year += 1
        }

        var result: [String] = ["全部"]
        for _ in 0..<5 {
            result.append("\(year)年\(month)月")
            if month == 1 {
                month = 10
                year -= 1
            } else {
                month -= 3
            }
        }
        return result
    }

    func loadAll() async {
        isLoading = true
        errorMessage = nil
        async let r: () = loadRankings()
        async let p: () = loadPopular()
        async let overlay: () = loadAllCollectionsForOverlay()
        _ = await (r, p, overlay)
        isLoading = false
    }

    func loadRankings() async {
        do {
            var filter = SubjectSearchFilter()
            filter.rank = [">0"]
            // All types — type filtering now happens in the pushed BrowseView.
            rankings = try await api.searchSubjects(keyword: "", filter: filter, sort: "rank").withoutNSFW
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPopular() async {
        do {
            var filter = SubjectSearchFilter()
            filter.rating = [">=7.0"]
            // "热门" = trending; the >=7.0 filter ensures 高分. (PRD mockup
            // annotates "按评分排序", but heat better matches "热门".)
            popularSubjects = try await api.searchSubjects(keyword: "", filter: filter, sort: "heat").withoutNSFW
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Seeds the SwiftData cache with the user's collections so carousel cards
    /// can render the correct status badge, then rebuilds the in-memory overlay
    /// map. No-op when not signed in.
    private func loadAllCollectionsForOverlay() async {
        guard await api.hasToken() else {
            collectionOverlay = [:]
            return
        }
        if let collections = try? await api.fetchUserCollections() {
            try? cache.cacheCollections(collections)
        }
        collectionOverlay = Self.buildCollectionOverlay(from: cache)
    }

    func collectionType(for subjectId: Int) -> CollectionType? {
        collectionOverlay[subjectId]
    }

    func addToWishlist(_ subject: Subject) async {
        do {
            // Shared CollectionService centralizes the API + cache dance.
            try await CollectionService(api: api, cache: cache).addToWishlist(subjectId: subject.id)
            // In-memory overlay so a subsequently-pushed BrowseView / carousel
            // card immediately reflects the new status.
            cache.upsertCachedCollectionType(subjectId: subject.id, type: .wish, subjectType: subject.type)
            collectionOverlay[subject.id] = .wish
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Parses a "2024年7月" season label into its year/month for BrowseConfig.
    func parsedSeason(_ label: String) -> (year: Int, month: Int)? {
        let scanner = Scanner(string: label)
        var year = 0, month = 0
        guard scanner.scanInt(&year) else { return nil }
        _ = scanner.scanString("年")
        guard scanner.scanInt(&month) else { return nil }
        return (year, month)
    }
}
