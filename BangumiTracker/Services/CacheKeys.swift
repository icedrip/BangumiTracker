import Foundation

/// Centralized namespace for UserDefaults / file-cache keys so they aren't
/// scattered as private static lets across individual ViewModels.
enum CacheKeys {
    // MARK: - Home
    enum Home {
        static let todayPick = "cache.home.todayPick"
        static let becauseYouWatch = "cache.home.becauseYouWatch"
        static let hiddenGems = "cache.home.hiddenGems"
        static let timeCapsule = "cache.home.timeCapsule"
        static let recommendationsLastLoadedDay = "cache.home.recommendationsLastLoadedDay"
        static let wishSort = "home.wishSort"
    }

    // MARK: - Profile
    enum Profile {
        static let userInfo = "cache.profile.userInfo"
        static let stats = "cache.profile.stats"
        static let genres = "cache.profile.genres"
        static let insights = "cache.profile.insights"
    }
}
